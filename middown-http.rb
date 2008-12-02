#!/usr/bin/env ruby

$LOAD_PATH << "theruck/lib"

require "rubygems"
require "theruck"
require "json"
require "erb"
require "pathname"

require "middown-daemon"
require "rinda/ring"
DRb.start_service

include TheRuck

class MiddownRoot < Controller

	route "" do
		show :index, :tasks => middown.tasks, :plugins => middown.plugins
	end

	route "static/*file" do
		file = Pathname.new(__FILE__).parent + "static/#{params["file"]}"
		if file.exist?
			require "webrick/httputils"
			mime_type = WEBrick::HTTPUtils.mime_type(params["file"], WEBrick::HTTPUtils::DefaultMimeTypes)
			head "Content-Type", mime_type
			body file.read
		else
			head 404
			head "Content-Type", "text/plain"
			body "Not Found"
		end
	end

	class ApiController < Controller
		route "progress.json" do
			json middown.tasks
		end

		route "remove.json", POST do
			if middown.tasks.include? {|i| i["ticket"] == params["ticket"] }
				ret = middown.remove_task(params["ticket"]).to_json
				json true
			else
				json({"error" => "unknown ticket"})
			end
		end

		route "add.json", POST do
			p params
			ret = middown.add_task(params["plugin"], params["uri"])
			if ret
				json ret
			else
				json({"error" => "unknown plugin"})
			end
		end

		route "plugins.json" do
			json middown.plugins
		end
	end

	route "api/*" => :ApiController

	def middown
		unless @middown
			ts = Rinda::RingFinger.primary
			begin
				tp = ts.read([:name, :Middown, DRbObject, nil], 0)
			rescue Rinda::RequestExpiredError
				raise "Not found"
			end
			@middown = tp[2]
		end
		@middown
	end

	def show(name, stash)
		body, *layouts = file("template/#{name}.rhtml"), file("template/layout.rhtml")

		s = OpenStruct.new(stash)
		def s._render(_template)
			_template.result(binding)
		end

		head "Content-Type", "text/html"
		body layouts.inject(s._render(ERB.new(body))) {|r,i|
			s.content = r
			s._render(ERB.new(i))
		}
	end

	def json(stash)
		head "Content-Type", "text/javascript"
		body stash.to_json
	end

	def file(name)
		filename = Pathname.new(__FILE__).parent + name
		filename.read
	end
end

if $0 == __FILE__
	Rack::Handler::WEBrick::run MiddownRoot, :Port => 4910
	# rackup -s webrick ./plusplus.rb
end
