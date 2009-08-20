require 'rubygems'
require 'mechanize'

agent = WWW::Mechanize.new

# TODO Use https?
login_url = 'http://developer.apple.com/iphone/login.action'

agent.get(login_url) do |login_page|
 
  # Submit the login form
  login_page.form_with(:name => "appleConnectForm") do |form|
    form["theAccountName"] = "etupil"
    form["theAccountPW"]   = "e^i09uT"
  end.submit
 
  # TODO Check for invalid credentials

  # After a succesful login we need to touch the login page again to establish a session
  agent.get(login_url)
  
  # program_portal = agent.click(account_page.link_with(:text => /iPhone Developer Program Portal/))
  # p program_portal

  add_device_page = agent.get("http://developer.apple.com/iphone/manage/devices/add.action")
  page = add_device_page.form_with(:name => "save") do |form|
    form["deviceNameList[0]"]   = "Test"
    form["deviceNumberList[0]"] = "12345678901234567890123456678901234567890"
  end.submit

  p page

end
