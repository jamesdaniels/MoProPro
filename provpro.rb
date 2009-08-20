#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'mechanize'
require 'yaml'

SETTINGS_FILE = '.provpro'

class ProvPro

  # Since the website only uses JavaScript for validation(!), we need do this
  # ourselves
  def validate(udid, name)
    if not name =~ /[\w\d ]+/
      puts "Error: name can only contain alphanumeric characters and spaces (but is: '#{name}')"
      exit
    end
    if not udid =~ /[a-fA-F\d]{40}/
      puts "Error: UDID must be a 40 character hexadecimal string (but is: '#{udid}')"
      exit
    end
  end

  def login
    login_url = 'https://developer.apple.com/iphone/login.action'
    form_name = 'appleConnectForm'
    
    @agent.get(login_url) do |login_page|
     
      # Submit the login form
      login_page.form_with(:name => form_name ) do |form|
        form["theAccountName"] = @username
        form["theAccountPW"]   = @password
      end.submit
     
      # After a succesful login we need to touch the login page again to establish a session
      # If we find the login form on this page, the login was not succesful
       if not @agent.get(login_url).forms.find { |f| f.name == form_name }.nil?
         STDERR << "Error: invalid credentials\n"
         exit
       end
    end
  end

  def add_devices(devices)
    add_device_page = @agent.get("https://developer.apple.com/iphone/manage/devices/add.action")
    page = add_device_page.form_with(:name => "save") do |form|
      index = 0
      devices.each_pair{ |udid, name|
        form["deviceNameList[#{index}]"]   = name
        form["deviceNumberList[#{index}]"] = udid
        index += 1
      }
    end.submit
    
    p page
  end

  def error_usage(error)
    STDERR << "Error: "
    STDERR << error
    STDERR << "\n\n"
    STDERR << @optparser.help
    exit
  end

  def initialize(args)
    settings = (YAML::load_file(SETTINGS_FILE) if File.exists?(SETTINGS_FILE)) || {}
    @username = settings["username"]
    @password = settings["password"]

    @optparser = OptionParser.new do |opts|
      opts.banner += " UDID name\n\n" + 

                    "You must provide credentials, either through the command line options\n" +
                    "or in a YAML file named '#{SETTINGS_FILE}'\n\n" +

                    "You can also use stdin to provide multiple device entries\n" +
                    "For example: 'cat devices.yml | #{opts.program_name}'\n\n"

      opts.on("-u", "--username USERNAME", "ADC Username") do |u|
        @username = u
      end
    
      opts.on("-p", "--password PASSWORD", "ADC Password") do |p|
        @password = p
      end
    end
    
    @optparser.parse!(args)
    
    error_usage("No username or password provided") if @username.nil? || @password.nil?
    error_usage("Not enough arguments")             if args.size != 2 && STDIN.tty?
    # else
    devices = {} 
    devices[args[0]] = args[1] if args.size == 2

    if not STDIN.tty?
      devices.merge!(YAML::load(STDIN))
    end

    devices.each_pair {|udid, name| validate(udid, name)}
    
    @agent = WWW::Mechanize.new
    login
    add_devices(devices)
  end
end

ProvPro.new(ARGV)
