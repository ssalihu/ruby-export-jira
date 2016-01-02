#
# Safir Salihu 11/2015
# This script is used to extract Jira entries based on Jira Query Language,
# manipulate or adjust the data and then write to a CSV file
# The extraction is executed by using REST API calls to the JIRA server
# There are many custom jira field adjustment methods are here in this script.
# These methods are not in any way or form standardized. The methods are just
# a means to show the different ways to manipulate the extracted JIRA data.
#

require 'rubygems'
require 'pp'
require 'jira'
require 'csv'
require 'highline/import'
require 'ruby-progressbar'

# User parameteres. Can be changed
# update your JIRA link here
SITE = 'https://jira.prjb2bqa.com/sr'
# add queries to this array
@jql_queries = [
"project = 'PRJ' AND issuetype = 'User Story' AND status NOT IN ('Closed')",
"project = 'PRJ' AND issuetype = 'User Story' AND status = Closed AND created < 2015-07-01",
"project = 'PRJ' AND issuetype = 'User Story' AND status = Closed AND created >= 2015-07-01"
 ]
# feel free to add your file name prefix or desintation
@FILE_NAME_SUFFIX = './extract-'


# Program defined parameters
@EXPORTS = Array.new
@username = ""
@password = ""
@client = ""
@data = Array.new

@data_to_extract = {
'status' => '',
'description' => '',
'type' => '',
'status' => '',
'priority' => '',
'resolution' => '',
'assignee' => '',
'reporter' => '',
'created' => '',
'updated' => '',
'resolved' => '',
'fixVersion' => '',
'customfield_12746' => '', #Acceptance Criteria
'customfield_10632' => '', #Assumptions
'customfield_15522' => '', #Sprint (Greenhopper Plugin)
'issuelinks' => '',
 'comment' => ''
}


# custom methods
def generate_random_file_suffix
	(0...8).map { (65 + rand(26)).chr }.join + '.csv'
end

def get_password(prompt="Enter Password")
	ask(prompt) {|q| q.echo = '*'}
end

# 
# Method to remap Priority field
#
def map_priority(priority)
	if priority['name'].include?('Minor')
		priority = 'Medium'
	elsif priority['name'].include?('Major')
		priority = 'High'
	else
		priority = priority['name']
	end
	priority	
end

def enrich_description(key,description)
	if !description.index("As").nil?
		new_description = description[description.index("As"), description.length]
	else
		new_description = description
	end
	new_description = "<p> #{key} </p><p> #{new_description}</p>" 
	new_description
end

def get_user(user)
	jira_user = Hash.new
  jira_user[user['name']] = user['displayName']
  jira_user
end

def get_user_id(user)
	users = get_user(user)
	id  = ''
	users.each do |id1,name|
		id = id1
	end
	id
end

def get_user_name(user)
	users = get_user(user)
	name = ''
	users.each do |id,n|
		name = n
	end
	name
end

# 
# Ugly logic to get the Sprint numbers from the 
# Sprint field
#
def get_sprint(sprints)
	if sprints.length > 0
		# s = sprints[0]
		s = sprints[sprints.length-1]
		beg = s.index("=") + 1
		endin = s[beg,s.length].index(",")
		s = s[beg, endin]
	end
	s
end

def total_sprints(sprint)
	sprint.length
end

def get_all_sprints(sprints)
	all = Array.new
	sprints.each do |sprint|
		s = sprint
		beg = s.index("=") + 1
		endin = s[beg,s.length].index(",")
		s = s[beg, endin]
		all << s
	end
	all
end

def get_linked_issues(linked_issues)
	linked_issue = Array.new
	if linked_issues.length>0
		linked_issues.each do |issuelink|
			if !issuelink['outwardIssue'].nil? 
				linked_issue << issuelink['outwardIssue']['key']
			end
			if !issuelink['inwardIssue'].nil? 
				linked_issue << issuelink['inwardIssue']['key']
			end
		end			
	end	
	linked_issue
end

def get_credentials
	print "Enter your jira username: "
	@username = gets.chomp
	@password = get_password()
	if @username.empty? or @password.empty?
		puts "... Username/password cannot be empty ..."
		exit
	end	
end

def show_jql
	puts "Queries in this run ...."
	@jql_queries.each do |query|
		puts "#{query}"
	end
	puts ""
	puts "-----------------------------------"
end

def read_more_jql
	print "Enter jql if you want to add more: "
	jql = gets.chomp
	if !jql.nil? && !jql.empty?
		@jql_queries << jql.chomp
	end
end

def make_jira_connection
	options = {
		:username => @username,
		:password => @password,
		:site     => SITE,
		:context_path => '/',
		:ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE,
		:auth_type => :basic,
		:read_timeout => 500
	}

	@client = JIRA::Client.new(options)
# Show all projects
#project = @client.Project.find('PRJ')

end

def setup_jira_query_options
	@query_options = {
		:fields => @data_to_extract.keys,
		:start_at => 0,
	#  CAUTION CAUTION CAUTION
	#  DO NOT EXCEED 1000, likely to  incapciate the JIRA server. :-(
		:max_results => 1000 
	}
end

def get_comments(comments)
	all_comments = ''
	if !comments.nil?
		 comments['comments'].each do |comment|
		 	# puts comment['created']
		 	# puts comment['author']['name']
		 	# puts comment['body']
		 	  all_comments = comment['created'] + "; " + comment['author']['name'] + ";" + comment['body'] + ";"
		 	end
	end
	all_comments
end

def make_file
	file_name = @FILE_NAME_SUFFIX + generate_random_file_suffix
  puts "Generating file name #{file_name}"
  @EXPORTS << file_name

end

def write_header
	file_name = @EXPORTS[0]
	puts "Writting header to #{file_name}"
	header = ['Key','Description','Linked Issues', 'Sprint','Has More Sprints','All Sprint','Priority','Assignee ID','Assignee', 'Reporter ID','Reporter', 'Comments']
	CSV.open(file_name, "w") do |csv|
		csv << header
	end		
end

def build_export_file
  puts "Now building csv file ..."
	header = ['Key','Description','Linked Issues', 'Sprint','Has More Sprints','All Sprints','Priority','Assignee ID','Assignee', 'Reporter ID','Reporter', 'Comments']
#  file_name = @FILE_NAME_SUFFIX + generate_random_file_suffix
#  @EXPORTS << file_name
  file_name = @EXPORTS[0]
  puts "Writing to file #{file_name}"
  delta = 0
  incr = 0
  if @data.length >= 100
    incr = @data.length / 100
  else
  	puts "here"
  	incr = 1 + (100 - @data.length)
  end
	CSV.open(file_name, "a") do |csv|
	#	csv << header
		@data.each do |row|
			csv << row
		end
	end
	@data = Array.new		
end

# summary is blank
# acceptace criteria if it has 'As a' it will be 
def process_queries
	@jql_queries.each do |query|
		puts "Now executing ... #{query}..."
		@client.Issue.jql(query, @query_options).each do |issue|

		#description massage new_description
		new_description= (issue.description.nil?) ? '' : enrich_description(issue.key.sub('PRJ','WPS'),issue.description)

    #Rename priority	
    priority = (issue.fields['priority'].nil?) ? '': map_priority(issue.fields['priority'])	

		#Get Linked-Issues
		linked_issue = (issue.issuelinks.nil?) ? '' : get_linked_issues(issue.issuelinks)

    # Get reporter info
    reporter_id = (issue.fields['reporter'].nil?) ? '' : get_user_id(issue.fields['reporter'])
    reporter = (issue.fields['reporter'].nil?) ? '' : get_user_name(issue.fields['reporter'])

    # Get assignee info
    assignee_id = (issue.fields['assignee'].nil?) ? '' : get_user_id(issue.fields['assignee'])
    assignee = (issue.fields['assignee'].nil?) ? '' : get_user_name(issue.fields['assignee'])

    # Get sprint - Dirt work is buried in the methods:-|
    sprint = (issue.customfield_15522.nil?) ? '' : get_sprint(issue.customfield_15522)

    #has more sprints- Messed up situation handling
    has_more_sprints = (issue.customfield_15522.nil?) ? '' : total_sprints(issue.customfield_15522)
    get_all_sprints = (issue.customfield_15522.nil?) ? Array.new  : get_all_sprints(issue.customfield_15522)

    # get the comments
    comments = get_comments(issue.comment)

    # Build the record
    # PRJ is replaced with WPS
    # Flatten all the linked issues to one string

    @data << [issue.key.sub('PRJ','WPS'),new_description,linked_issue.map{|x| x.sub('PRJ','WPS')}.join(' '),
    	sprint,has_more_sprints,get_all_sprints.join(" and "),priority,assignee_id,assignee,reporter,reporter_id, comments]

    end
    build_export_file
 end

end

def print_export_file
	puts "Exports are available here: "
	@EXPORTS.each do |file|
		puts file
	end
end


# Let us do it here
get_credentials
read_more_jql
setup_jira_query_options
make_jira_connection
show_jql
make_file
write_header
process_queries
print_export_file

