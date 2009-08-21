#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'mechanize'
require 'yaml'
require 'plist'

SETTINGS_FILE = '.mopropro'

class MoProPro

  # Since the website only uses JavaScript for validation(!), we need do this
  # ourselves
  def validate(udid, name)
    if not name.match(/^[a-z\d ]+$/i)
      puts "Error: name can only contain alphanumeric characters and spaces (but is: '#{name}')"
      exit
    end
    if not udid.match(/^[a-f\d]{40}$/i)
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
         error("Invalid credentials")
         exit
       end
    end

    status_end()
  end

  def filter_devices(devices)
    status_start("Looking up existing devices")
    
    device_page = @agent.get("https://developer.apple.com/iphone/manage/devices/index.action")

    existing_names = []
    device_page.root.search('td.name span').each do |name|
      existing_names << name.content
    end

    existing_udids = []
    device_page.root.search('td.id').each do |id|
      existing_udids << id.content
    end

    filtered_devices = devices.reject do |udid, name|
      idx = existing_udids.index(udid)
      if not idx.nil?
        substatus("Warning: Device UDID #{udid} already exists, with name '#{existing_names[idx]}'.")
        true
      end
    end

    status_end("Done.")

    filtered_devices
  end

  def add_devices(devices)
    if (devices.size == 0)
    status_start("No new devices to be added")
    status_end("")
    return

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

  def get_profiles_with_link(matching)
    profiles_page = @agent.get("http://developer.apple.com/iphone/manage/provisioningprofiles/viewDistributionProfiles.action")
    profiles = []
    # Names
    profiles_page.root.search('td.profile span').each_with_index do |span,i|
      profiles[i] = {:name => span.content}
    end
    # Bundle identifiers (without seed)
    profiles_page.root.search('td.appid').each_with_index do |appid,i| 
      profiles[i].merge!({:app_id => appid.content.sub(/^[\w\d]+\./, '')})
    end
    # Edit links
    profiles_page.links_with(matching).each_with_index do |link,i|
      profiles[i].merge!({:link => link})
    end

    profiles
  end

  def modify_provisioning_profile(app_id, devices)
    status_start("Looking up provisioning profile")

    profiles = get_profiles_with_link(:text => 'Modify')
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
      edit_page = @agent.click(profile[:link])
      form = edit_page.form_with(:name => "saveDistribution")
      # Check if this is an Ad Hoc profile
      if form.radiobutton_with(:value => "limited").checked
        # Fix a hidden input, normally done by JavaScript
        form["distributionMethod"] = "limited"
        substatus("Found Ad Hoc profile")
        substatus("Adding devices")
        devices.each_key do |udid|
          form.checkbox_with(:value => udid).checked = true
        end
        status_start("Saving profile with new devices")
        form.submit
        status_end()
        
        # Return the profile we adjusted.  It will get a new link, but we can
        # use the name and app_id to match the right one
        return profile
      end
    end
  end
  
  def retrieve_new_profile(profile)
    status_start("Waiting a bit while the new profile is generated")
    sleep 3
    status_end

    status_start("Trying to retrieve new profile")

    for try in 1..3
      profiles = get_profiles_with_link(:href => /download.action/)
      if profiles[-1].has_key?(:link)
        break
      else
        seconds = (try * 2) ** 2
        substatus("Pending, trying again after #{seconds} seconds")
        sleep seconds
      end
    end
    
    error("Still pending, bailing out.  Sorry!") if not profiles[-1].has_key?(:link)
    # else
    
    download_link = profiles.collect do |pr| 
      pr[:link] if pr[:name] == profile[:name] && pr[:app_id] == profile[:app_id]
    end.compact.first

    error("No matching profile found?  Bailing out, sorry!") if not download_link
    # else
    
    file = @agent.click(download_link)
    file.save
    status_end("Got it!")

    STDOUT << "Saved new provisioning profile to '#{file.filename}'\n"    
  end

  def error(message)
    STDERR << "Error: "
    STDERR << message
    STDERR << "\n"
    exit
  end

  def error_usage(message)
    error(message << "\n\n" << @optparser.help)
  end

  def status_start(message)
    return if not @verbose
    STDOUT << message << "... "
    STDOUT.flush
    @status_open = true
  end

  def status_end(message = "Ok.")
    return if not @verbose
    STDOUT << message
    STDOUT << "\n"
    STDOUT.flush
    @status_open = false
  end

  def substatus(message)
    return if not @verbose
    STDOUT << "\n" if @status_open
    STDOUT << " - " << message << "\n"
    STDOUT.flush
    @status_open = false
  end

  def initialize(args)
    settings = (YAML::load_file(SETTINGS_FILE) if File.exists?(SETTINGS_FILE)) || {}
    username = settings["username"]
    password = settings["password"]
    noprov   = settings["provisioning"]
    @verbose = settings["verbose"]

    @status_open = false

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

    begin
      @agent = WWW::Mechanize.new
      login(username, password)
      filtered_devices = filter_devices(devices)
      add_devices(filtered_devices)
      if not noprov
        profile = modify_provisioning_profile(app_id, devices)
        error("No matching Ad Hoc provisioning profile found") if not profile
        retrieve_new_profile(profile)
      end
    rescue WWW::Mechanize::ResponseCodeError => ex
      error("HTTP #{ex.message}")
    end
  end
end

MoProPro.new(ARGV)
