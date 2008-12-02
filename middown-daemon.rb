#!/usr/bin/env ruby

require "pathname"
require "ostruct"
require "drb/drb"

require "open3" # only works on unix
require "digest/sha1"

require "optparse"

module Middown
	class Daemon
		attr_reader :config
		attr_reader :tasks

		def initialize(config={})
			@config = OpenStruct.new(config)
			@config.plugin_dir = Pathname.new(@config.plugin_dir)
			@tasks  = []
		end

		def add_task(plugin, uri)
			exe = @config.plugin_dir + plugin
			if exe.exist?
				dest = config.dest

				ticket = Digest::SHA1.hexdigest(plugin + uri + Time.now.to_s + rand.to_s)
				puts [plugin, uri, ticket]

				task = Thread.start(dest, uri) do |d, u|
					Thread.abort_on_exception = true
					task = Thread.current
					task[:progress] = 0

					puts [exe, u, d]
					stdin, stdout, stderr = *Open3.popen3(exe, u, d)
					stdin.close

					task[:pid] = stdout.pid

					Thread.start(stderr) do |err|
						task[:error] = err.read
						task.kill
					end
					while l = stdout.gets
						puts l
						task[:progress] = l.chomp.to_f
					end
				end

				task[:ticket] = ticket
				task[:start]  = Time.now
				task[:uri]    = uri
				task[:plugin] = plugin

				@tasks << task

				ticket
			else
				nil
			end
		end

		def remove_task(ticket)
			@tasks.reject! do |t|
				if t[:ticket] == ticket
					begin
						t.kill
						Process.kill(t[:pid])
					rescue
					end
					true
				end
			end
		end

		def tasks
			@tasks.reverse.map { |t|
				t.keys.inject({}) {|r,i| r.update(i => t[i]) }
			}
		end

		def plugins
			Dir.glob(@config.plugin_dir + "*").map {|i| File.basename(i) }
		end
	end

	class CLI
		VERSION = "0"
		NAME    = "middown"

		def self.run(argv)
			new(argv.dup).run
		end

		def initialize(argv)
			@argv = argv

			@subparsers = {
				"help" => OptionParser.new { |opts|
					opts.banner = <<-EOB.gsub(/^\t+/, "")
						Usage: #{NAME} help <subcommand>

						Show help of subcommand.
					EOB
				},

				"add" => OptionParser.new { |opts|
					opts.banner = <<-EOB.gsub(/^\t+/, "")
						Usage: #{NAME} add <uri> [<plugin>]

						Add uri to task.
					EOB
				},

				"del" => OptionParser.new { |opts|
					opts.banner = <<-EOB.gsub(/^\t+/, "")
						Usage: #{NAME} del <ticket>

						Delete task named as <ticket>.
					EOB
				},

				"progress" => OptionParser.new { |opts|
					opts.banner = <<-EOB.gsub(/^\t+/, "")
						Usage: #{NAME} progress

						Show progress.
					EOB
				},
			}

			@parser = OptionParser.new do |parser|
				parser.banner  = <<-EOB.gsub(/^\t+/, "")
					Usage: #{NAME} <subcommand> <args>

				EOB

				parser.separator ""

				parser.separator "Subcommands:"
				@subparsers.keys.sort.each do |k|
					parser.separator "#{parser.summary_indent}    #{k}"
				end

				parser.separator ""

				parser.separator "Options:"
				parser.on('--version', "Show version string `#{VERSION}'") do
					puts VERSION
					exit
				end
			end
		end

		def run
			@parser.order!(@argv)
			if @argv.empty?
				puts @parser.help
				exit
			else
				require "rinda/ring"
				require "rinda/tuplespace"
				DRb.start_service

				ts = Rinda::RingFinger.primary
				tp = ts.read([:name, :Middown, DRbObject, nil])
				@middown = tp[2]


				@subcommand = @argv.shift
				method_name = "cmd_#{@subcommand}"
				if self.respond_to?(method_name)
					@subparsers[@subcommand].parse!(@argv)
					self.send(method_name)
				else
					cmd_progress
				end
			end
		end


		def cmd_add
			uri, plugin, = @argv
			plugin ||= "http"

			puts @middown.add_task(plugin, uri)
		end

		def cmd_del
			ticket, = @argv

			puts @middown.remove_task(ticket)
		end

		def cmd_progress
			@middown.tasks.each do |t|
				t = OpenStruct.new(t)
				puts "%s: % 3.2f%% / %s %s" % [t.ticket, t.progress * 100, t.uri, t.error]
			end
		end
	end
end


if $0 == __FILE__

	require "rinda/ring"
	require "rinda/tuplespace"
	DRb.start_service

	ts = Rinda::TupleSpace.new
	rs = Rinda::RingServer.new(ts)

	m = Middown::Daemon.new({ :dest => "/tmp", :plugin_dir => "./plugins" })

	provider = Rinda::RingProvider.new(:Middown, DRbObject.new(m), 'Middown')
	provider.provide

	puts "Booted"
	sleep
end
