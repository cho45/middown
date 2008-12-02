#!/usr/bin/env ruby

require "pathname"
require "ostruct"
require "drb/drb"

require "open3" # only works on unix
require "digest/sha1"

require "optparse"

$uri = "druby://localhost:54954" #TODO

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

					puts [exe, u, d]
					stdin, stdout, stderr = *Open3.popen3(exe, u, d)
					stdin.close
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
			end
		end

		def remove_task(ticket)
			@tasks.reject! do |t|
				t[:ticket] == ticket
			end
		end

		def tasks
			@tasks.reverse.map { |t|
				OpenStruct.new(t.keys.inject({}) {|r,i| r.update(i => t[i]) })
			}
		end

		def plugins

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

			middown = DRbObject.new_with_uri($uri)
			puts middown.add_task(plugin, uri)
		end

		def cmd_del
			ticket, = @argv

			middown = DRbObject.new_with_uri($uri)
			puts middown.remove_task(ticket)
		end

		def cmd_progress
			middown = DRbObject.new_with_uri($uri)
			middown.tasks.each do |t|
				puts "%s: % 3d%% %s" % [t.ticket, t.progress, t.error]
			end
		end
	end
end


if $0 == __FILE__
	m = Middown::Daemon.new({ :dest => "/tmp", :plugin_dir => "./plugins" })
	DRb.start_service($uri, m)
	puts DRb.uri
	sleep
end
