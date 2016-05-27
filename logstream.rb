#!/usr/bin/env ruby

require 'socket'
require 'json'
require 'chef'
require 'chef/knife'
require 'chef/knife/search'
require 'chef/knife/data_bag_show'
require 'highline'

def knife(cmd, *args)
  Chef::Config.from_file(File.expand_path('/etc/chef/knife.rb'))
  classname = "Chef::Knife::#{cmd}"
  knife = Object.const_get(classname).new

  knife.name_args = args
  knife.config[:format] = 'json'

  out = StringIO.new
  err = StringIO.new
  knife.ui = Chef::Knife::UI.new(out, err, STDIN, knife.config)
  knife.run

  return JSON.parse(out.string)
end

def databag_show(databag)
  return knife('DataBagShow', databag)
end

def node_search(filter)
  result = knife('Search', 'node', filter)
  return result['rows'].map{|h| h['name']}
end

cli = HighLine.new
apps = databag_show('srm_components')

app, env, log = ""
loop do 
  trap("INT") { puts "\nExiting..." ; exit }

  cli.choose do |menu|
    menu.header = "app: #{app}    env: #{env}     log: #{log}"
    menu.choice(:app) do
      app = cli.choose do |app_menu|
        app_menu.header = "Select app"
        app_menu.layout = :one_line
        app_menu.choices(*apps)
      end
    end
    menu.choice(:env) do
      env = cli.choose do |env_menu|
        env_menu.header = "Select environment"
        env_menu.choices('staging', 'integration')
      end
    end
    menu.choice(:log) do
      log = cli.choose do |log_menu|
        log_menu.header = "Select log"
        log_menu.choices( *%W[#{env} unicorn nginx resque subscribers notifications-rmq] )
      end
    end
    menu.choice(:done) do
      if app && env && log
        hosts = node_search("roles:srm_#{app} AND chef_environment:#{env}")
        
        sock = TCPSocket.new('localhost', 5555)

        interrupt = false
        trap("INT") { interrupt = true }

        puts "Starting log stream..."
        while line = sock.gets # Read lines from socket
          json = JSON.parse(line)         # and print them
          host = json['host']
          type = json['type']
          message = json['message']
          puts "#{host} - #{type} - #{message}" if json['type'] == log && hosts.include?(host)
          if interrupt == true
            sock.close
            break
          end
        end
      else
        puts "Please set all filters"
      end
    end
  end    
end
