#!/usr/bin/env ruby

# TODO
# - Create a new provisioning profile
#   - Wait for the new profile to be generated
#   - Download the profile

require 'rubygems'
require 'optparse'
require 'mechanize'
require 'yaml'
require 'plist'

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

  def login(username, password)
    status_start("Logging in")

    login_url = 'https://developer.apple.com/iphone/login.action'
    form_name = 'appleConnectForm'
    
    @agent.get(login_url) do |login_page|
     
      # Submit the login form
      login_page.form_with(:name => form_name ) do |form|
        form["theAccountName"] = username
        form["theAccountPW"]   = password
      end.submit
     
      # After a succesful login we need to touch the login page again to establish a session
      # If we find the login form on this page, the login was not succesful
       if not @agent.get(login_url).forms.find { |f| f.name == form_name }.nil?
         STDERR << "Error: invalid credentials\n"
         exit
       end
    end

    status_end()
  end

  def add_devices(devices)
    status_start("Adding #{devices.size} device#{devices.size == 1 ? "" : "s"}")

    add_device_page = @agent.get("https://developer.apple.com/iphone/manage/devices/add.action")
    page = add_device_page.form_with(:name => "save") do |form|
      index = 0
      devices.each_pair{ |udid, name|
        form["deviceNameList[#{index}]"]   = name
        form["deviceNumberList[#{index}]"] = udid
        index += 1
      }
    end.submit

    status_end("Submitted.")
  end

  def modify_provisioning_profile(app_id, devices)
    status_start("Looking up provisioning profile")

    profiles_page = @agent.get("http://developer.apple.com/iphone/manage/provisioningprofiles/viewDistributionProfiles.action")
    profiles = []
    # Names
    profiles_page.root.search('td.profile span').each_with_index do |span,i|
      profiles[i] = { :name => span.content }
    end
    # Bundle identifiers (without seed)
    profiles_page.root.search('td.appid').each_with_index do |appid,i| 
      profiles[i].merge!({:app_id => appid.content.sub(/^[\w\d]+\./, '')})
    end
    # Edit links
    profiles_page.links_with(:text => 'Modify').each_with_index do |link,i|
      profiles[i].merge!({:edit_link => link})
    end

    substatus("Found #{profiles.size} profile#{profiles.size == 1 ? "" : "s"}")

    # Try to find exact matches
    matching_profiles = profiles.find_all do |profile|
      profile[:app_id] == app_id
    end
    # Else, filter out profiles that don't match our app_id
    matching_profiles = profiles.find_all do |profile|
      # (Ab)use the bundle identifier as regex
      profile[:app_id] == "*" || app_id =~ /#{profile[:app_id]}/
    end if matching_profiles == []
  
    substatus("Found #{matching_profiles.size} matching profile#{matching_profiles.size == 1 ? "" : "s"}")

    # Sort profiles, prefer ones with "Ad Hoc" in their name
    matching_profiles.sort! do |a,b| 
      aah = (a[:name] =~ /Ad ?Hoc/i).nil?
      bah = (b[:name] =~ /Ad ?Hoc/i).nil?
      return 0 if aah == bah 
      (aah ? 1 : -1)
    end

    # Visit each of the matching profiles until we find an Ad Hoc profile
    matching_profiles.each do |profile|
      edit_page = @agent.click(profile[:edit_link])
      form = edit_page.form_with(:name => "saveDistribution")
      # Check if this is an Ad Hoc profile
      if form.radiobutton_with(:value => "limited").checked
        devices.each_key do |udid|
          form.checkbox_with(:value => udid).checked = true
        end
        p form
        # form.submit
        return # TODO
      end
      # p edit_page
    end

    # TODO: Error if no matching profile was found
  end

  def error_usage(error)
    STDERR << "Error: "
    STDERR << error
    STDERR << "\n\n"
    STDERR << @optparser.help
    exit
  end

  def status_start(message)
    return if not @verbose
    STDOUT << message
    STDOUT << "... "
    STDOUT.flush
  end

  def status_end(message = "Ok.")
    return if not @verbose
    STDOUT << message
    STDOUT << "\n"
    STDOUT.flush
  end

  def substatus(message)
    return if not @verbose
    STDOUT << "\n - "
    STDOUT << message
    STDOUT.flush
  end

  def initialize(args)
    settings = (YAML::load_file(SETTINGS_FILE) if File.exists?(SETTINGS_FILE)) || {}
    username = settings["username"]
    password = settings["password"]
    noprov   = settings["provisioning"]
    @verbose = settings["verbose"]

    @optparser = OptionParser.new do |opts|
      opts.banner += " UDID name\n\n" + 

                    "You must provide credentials, either through the command line options\n" +
                    "or in a YAML file named '#{SETTINGS_FILE}'\n\n" +

                    "You can also use stdin to provide multiple device entries\n" +
                    "For example: 'cat devices.yml | #{opts.program_name}'\n\n" +

                    "This program will look for an Info.plist file in the current directory\n" +
                    "to get the app identifier from (unless you specify --no-provisioning)\n\n"

      opts.on("-u", "--username USERNAME", "ADC Username") do |u|
        username = u
      end
    
      opts.on("-p", "--password PASSWORD", "ADC Password") do |p|
        password = p
      end

      opts.on("--no-provisioning", "Do not create a provisioning profile, only add devices") do |np|
        noprov = true
      end
      
      opts.on("-v", "--verbose", "Be verbose") do |v|
        @verbose = true
      end
    end
    
    @optparser.parse!(args)
    
    error_usage("No username or password provided") if username.nil? || password.nil?
    error_usage("Not enough arguments")             if args.size != 2 && STDIN.tty?
    error_usage("No Info.plist file found")         unless noprov || File.exist?('Info.plist')
    # else

    devices = {} 
    devices[args[0]] = args[1] if args.size == 2

    if not STDIN.tty?
      devices.merge!(YAML::load(STDIN))
    end

    status_start("Validating input")
    devices.each_pair {|udid, name| validate(udid, name)}
    status_end()

    if not noprov
      status_start("Getting App Id")
      app_id = Plist::parse_xml('Info.plist')["CFBundleIdentifier"] unless noprov
      status_end("#{app_id}")
    end

    @agent = WWW::Mechanize.new
    login(username, password)
    add_devices(devices)
    modify_provisioning_profile(app_id, devices) unless noprov
  end
end

ProvPro.new(ARGV)
