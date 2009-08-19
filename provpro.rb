require 'rubygems'
require 'mechanize'

agent = WWW::Mechanize.new

# TODO Use https?
login_url = 'http://developer.apple.com/iphone/login.action'

agent.get(login_url) do |login_page|
 
  # Submit the login form
  login_page.form_with(:name => /appleConnectForm/) do |form|
    form["theAccountName"] = "etupil"
    form["theAccountPW"]   = "e^i09uT"
  end.submit
  
  # TODO Check for invalid credentials

  # After a succesful login we go the login page again and get redirected.
  account_page   = agent.get(login_url)
  program_portal = agent.click(account_page.link_with(:name => /iPhone Developer Program Portal/))

  p program_portal
end
