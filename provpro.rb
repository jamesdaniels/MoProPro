#!/usr/bin/env ruby

require 'optparse'
require 'rubygems'
require 'mechanize'

class ProvPro

  # Since the website only uses JavaScript for validation(!), we need do this
  # ourselves
  def validate(name, udid)
    if not name =~ /[\w\d ]+/
      puts "Error: name can only contain alphanumeric characters and spaces"
      exit
    end
    if not udid =~ /[a-fA-F\d]{40}/
      puts "Error: UDID must be a 40 character hexadecimal string"
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
     
      # TODO Check for invalid credentials
    
      # After a succesful login we need to touch the login page again to establish a session
      # If we find the login form on this page, the login was not succesful
       if not @agent.get(login_url).forms.find { |f| f.name == form_name }.nil?
         STDERR << "Error: invalid credentials\n"
         exit
       end
    end
  end

  def add_device(name, udid)
    add_device_page = @agent.get("https://developer.apple.com/iphone/manage/devices/add.action")
    page = add_device_page.form_with(:name => "save") do |form|
      form["deviceNameList[0]"]   = name
      form["deviceNumberList[0]"] = udid
    end.submit
    
    p page
  end

  def initialize(args)
    optionParser = OptionParser.new do |opts|
      opts.banner = "Usage: provpro.rb [options] name UDID"
    
      opts.on("-u", "--username USERNAME", "ADC Username") do |u|
        @username = u
      end
    
      opts.on("-p", "--password PASSWORD", "ADC Password") do |p|
        @password = p
      end
    end
    
    optionParser.parse!(args)
    
    if @username.nil? || @password.nil?
      STDERR << "Error: no username or password provided\n"
      STDERR << optionParser.help
    end

    if args.size != 2
      STDERR << "Error: not enough arguments\n"
      STDERR << optionParser.help
      exit
    end
    # else
    
    validate(args[0], args[1])
    
    @agent = WWW::Mechanize.new
    login
    add_device(args[0], args[1])
  end
end

ProvPro.new(ARGV)

# "etupil"
# "e^i09uT"
