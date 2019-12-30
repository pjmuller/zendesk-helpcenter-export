# coding: utf-8
require 'rubygems'
require 'httparty'
require 'fileutils'
require 'json'
require 'uri'
require 'optparse'
require 'rbconfig'


# # Ruby script to export your Zendesk helpcenter
#
# Script based on https://github.com/skipjac/pull-zendesk-forums
# (which exports the forum, not the help center article)
#
# it uses the Zendesk API to export all categories, sections, articles, article_attachments to html (and json)
# all of this in a nested folder structure
#
#   - category
#     - section
#       - article
#         - article.html
#         - image-1.jpg
#         - image-2.png
#   - meta_data.json
#
# Bonus: it is smart in that when you rename a category, section, article it won't
# start to create duplicate folders but renames the old ones.
# The script can thus be used for both a new dump as updating an existing one.
#
# # How to use?
#
# 1. have a machine with ruby and rubygems installed
# (if you don't know how to do this, this script is probably out of your leage)
#
# 2. copy this .rb file to the place where you want to store the export
# 3. use terminal to navigate to the folder and run
#
#     ruby zendesk-helpcenter-export.rb -e yourzenmail@domain.com -p YoUrPassWoRd -d my-zen-subdomain
#
# # Contribute
#
# Feel free to create a pull request to improve this script
#
# # Credits
#
# - thanks to https://github.com/skipjac/pull-zendesk-forums
# - Author of this script: https://github.com/pjmuller
# - License: MIT
#
class ExportHelpCenter
  include HTTParty


  attr :raw_data, :log_level, :output_type
  LOG_LEVELS = {standard: 1, verbose: 2}
  OUTPUT_TYPES = [:slugified, :id_only]
  REQUIRED_INPUTS = [:email, :password, :subdomain]


  def initialize(options)
    exit unless invalid_inputs?(options)
    # prep variables
    @auth = {username: options[:email], password: options[:password]}
    @log_level = options[:log_level]
    @output_type = options[:output_type]
    # used to make one big dumpfile of all metadata related to your helpcenter
    @raw_data = {categories: []}
    # configure Httparty base uri
    self.class.base_uri "https://#{options[:subdomain]}.zendesk.com"
  end

  # section: loop over all categories, sections, articles and attachments
  # ---------------------------------------

  def to_html!
    return if api_error?(categories)

    categories['categories'].each do |category|
      log(category['name'].upcase)
      category_dir = dir_path(category)
      category_file_path = "#{category_dir}index.html"

      category[:sections] = []
      sections(category['id'])['sections'].each do |section|
        log("  #{section['name']}")
        section_dir = dir_path(category, section)
        section_file_path = "#{section_dir}index.html"

        section[:articles] = []
        articles(section['id'])['articles'].each do |article|
          log("    #{article['name']}", :standard)
          article_dir = dir_path(category, section, article)
          article_file_path = "#{article_dir}index.html"

          article[:attachments] = []
          article_attachments(article['id'])['article_attachments'].each do |attachment|
            article[:attachments] << attachment
            # optimization, do not download attachment when already present (we could check based on the id)
            download_attachment!(attachment, article_dir)
          end

          article['backup_path'] = article_file_path
          section[:articles] << article
          File.open(article_file_path, "w+") { |f| f.puts article_html_content(article) }

        end

        section['backup_path'] = section_file_path
        category[:sections] << section
      end

      category['backup_path'] = category_file_path
      @raw_data[:categories] << category
    end
  end

  # can only be called AFTER export_html_and_images!
  def to_json!
    File.open("./meta_data.json", "w+") { |f| f.puts JSON.pretty_generate(raw_data) }
  end

  def create_table_of_contents!
    all_overview_files.each do |path, html|
      File.open("#{path}", "w+") { |f| f.puts html }
    end
  end

  # Section: Article content
  # ---------------------------------------

  def article_html_content(article)
    # add some boilerplat to make it all look nicer
    # and replace all image links towards the local url
    regex_find = /https:\/\/.+?zendesk.com.+?article_attachments\/(\d+?)\/(.+)\.(.+?)" alt/
    regex_replace = output_type == :slugified ? '\1-\2.\3" alt' : '\1.\3" alt'

    # TODO: Enable internal links
    #  Replace "https://xxxx.zendesk.com/hc/..." → <category>/<section>/<article>/...

    boiler_plate_html do
      """
      <h1>#{article['name']}</h1>
      #{article['body'].to_s.gsub(regex_find, regex_replace)}
      """
    end
  end

  def main_overview_file
    root_overview_file(true)
  end

  def root_overview_file(recursive = false)
    boiler_plate_html do
      content = []
      content << "<ul>"
      raw_data[:categories].each do |cat|
        content << "<li>"
        content << "<h1 id='category-#{cat['id']}'><a href='#{cat['backup_path']}'>#{cat['name']}</a></h1>"
        if recursive == true
          content << category_overview_file(cat, recursive)
        end
        content << "</li>"
      end
      content << "</ul>"
      content.join("\n")
    end
  end

  def category_overview_file(category, recursive = false)
    boiler_plate_html do
      content = []
      content << "<h1>#{category['name']}</h1>" if !recursive
      content << "<ul>"
      category[:sections].each do |section|
        content << "<li>"
        if recursive == true
          content << "<h2 id='section-#{section['id']}'><a href='#{section['backup_path']}'>#{section['name']}</a></h2>"
          content << section_overview_file(section, recursive)
        else
          content << "<h2 id='section-#{section['id']}'><a href='./#{section['id']}/index.html'>#{section['name']}</a></h2>"
        end
        content << "</li>"
      end
      content << "</ul>"
      content.join("\n")
    end
  end

  def section_overview_file(section, recursive = false)
    boiler_plate_html do
      content = []
      content << "<h2>#{section['name']}</h2>" if !recursive
      content << "<ul>"
      section[:articles].each do |article|
        content << "<li>"
        if recursive == true
          content << "<h3 id='article-#{article['id']}'><a href='#{article['backup_path']}'>#{article['name']}</a></h3>"
        else
          content << "<h3 id='article-#{article['id']}'><a href='./#{article['id']}/index.html'>#{article['name']}</a></h3>"
        end
        content << "</li>"
      end
      content << "</ul>"
      content.join("\n")
    end
  end

  def all_overview_files
    files = {'./index.html': main_overview_file}

    raw_data[:categories].each do |cat|
      files[cat['backup_path']] = category_overview_file(cat)
      cat[:sections].each do |section|
        files[section['backup_path']] = section_overview_file(section)
      end
    end

    files
  end

  def boiler_plate_html &block
        """
<html>
  <head>
    <meta charset='UTF-8'>
    <link rel='stylesheet' href='http://output.jsbin.com/gefofo.css' />
  </head>
  <body>
    <div id='container'>
    #{yield}
    </div>
  </body>
</html>
    """
  end

  # section: Debugging
  # ---------------------------------------
  # input:
  # - text: text to log
  # - level: :standard / :verbose. States when it needs to be logged
  def log(text, level = :standard)
    # protect against bad input
    return unless LOG_LEVELS.has_key?(level)

    # output when the log level we are requesting
    puts text if LOG_LEVELS[log_level] >= LOG_LEVELS[level]
  end

  def invalid_inputs?(options)
    if REQUIRED_INPUTS.map{|k| options[k].nil?}.any?
      puts "Missing one of required inputs.\nExpecting: #{REQUIRED_INPUTS}.\nReceived = #{options}"
      return false
    end

    unless LOG_LEVELS.include?(options[:log_level])
      puts "Log level (#{options[:log_level]}) not recognized. Should be one of the values: #{LOG_LEVELS}"
      return false
    end

    unless OUTPUT_TYPES.include?(options[:output_type])
      puts "Ouput type (#{options[:output_type]}) not recognized. Should be one of the values: #{OUTPUT_TYPES}"
      return false
    end

    return true
  end

  # section: Make sure directories exist
  # ---------------------------------------

  # return the dir_path (string) for given resource
  # and create the path if does not exist yet
  def dir_path(category, section = nil, article = nil)
    # each resource has an id and name attribute
    # let's use this to build a path where we can store the actual data
    log("      buidling dir_path for #{[category, section, article].compact.map{|r| r['name']}}", :verbose)
    [category, section, article].compact.inject("./") do |dir_path, resource|
      # check if we have existing folder that needs to be renamed
      path_to_append = output_type == :slugified ? "#{resource['id']}-#{slugify(resource['name'])}" : "#{resource['id']}"
      rename_dir_or_file_starting_with_id!(dir_path, resource['id'], path_to_append)
      # build path and check if folder exists
      log("      #{path_to_append} appended to #{dir_path}", :verbose)
      dir_path += path_to_append + "/"
      Dir.mkdir(dir_path) unless File.exists?(dir_path)
      # end point is begin point of next iteration
      dir_path
    end
  end


  # input
  # - "/1001-categories/", "2001", "best section"
  # processing
  # - look if we find a directory that starts with 2001 in /1001-categories/
  #   e.g. /1001-categories/2001-better-section
  #   and if so, rename towards
  # output
  # - false if nothing needs renamed
  # - true if a dir was renamed
  def rename_dir_or_file_starting_with_id!(current_directory, id, should_be_name_for_item)
    current_name_for_item = Dir.entries(current_directory).select do |entry|
      entry.start_with?(id.to_s)
    end.first

    # dir or file not found, nothing to rename
    return false unless current_name_for_item
    # dir or file exists, but already with correct name
    return false if current_name_for_item == should_be_name_for_item

    log("      renaming #{current_directory}#{current_name_for_item}} to #{current_directory}#{should_be_name_for_item}", :verbose)
    FileUtils.mv "#{current_directory}#{current_name_for_item}", "#{current_directory}#{should_be_name_for_item}"
    return true
  end

  def slugify(text)
    text.to_s.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
  end

  # section: API calls
  # ---------------------------------------
  def api(url)
    options = {:basic_auth => @auth}
    self.class.get("/api/v2/help_center/#{url}", options)
  end

  def api_error?(api_response)
    if api_response.code != 200
      puts "Could not connect to the Zendesk API."
      puts "Most likely you provided incorrect username / password / zendesk domain."
      puts "\n\n"
      puts "Here is the full response of the failed zendesk API call"
      puts "-------------------------------------------------------"
      puts "request: #{api_response.request.path}"
      puts "status: #{api_response.headers['status']}"
      puts "headers: #{api_response.headers.inspect}"
      puts ""
      puts "response: #{api_response.response.inspect}"
      puts "parsed response: #{api_response.parsed_response.inspect}"
      true
    else
      false
    end
  end


  # see documentation on https://developer.zendesk.com/rest_api/docs/help_center/introduction
  def categories()          api("categories.json")                          end
  def sections(category_id) api("categories/#{category_id}/sections.json")  end
  def articles(section_id)  api("sections/#{section_id}/articles.json")     end
  def article_attachments(article_id)  api("articles/#{article_id}/attachments.json") end


  def download_attachment!(article_attachment, store_in_dir)
    file_name = "#{article_attachment['id']}#{output_type == :slugified ? "-#{article_attachment['file_name']}" : "#{File.extname(article_attachment['file_name'])}"}"
    # rename file if it existed with same id but incorrect name
    rename_dir_or_file_starting_with_id!(store_in_dir, article_attachment['id'], file_name)

    # if file with same id already present, do not "redownload"
    return true if Dir.entries(store_in_dir).select{|e| e.start_with?(article_attachment['id'].to_s)}.length > 0
    log("      #{article_attachment['file_name']}")

    begin
      options = {:basic_auth => @auth}
      file_contents = self.class.get(article_attachment['content_url'], options)
      file_path = "#{store_in_dir}#{file_name}"
      File.open(file_path, "w+") { |f| f.puts file_contents }
    rescue Exception => e
      log("      !!! failed download: " + article_attachment['content_url'] + ". error: #{e.message}")
    end
  end
end

# section: Executing the script
# ---------------------------------------


# default options (different between Microsoft windows and other OS)
is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
options = {
  log_level: :standard,
  output_type: is_windows ? :id_only : :slugified
}

# step 1: get the attributes through the params
OptionParser.new do |opts|
  opts.banner = "Usage: zendesk-helpcenter-export.rb [options]"
  opts.on('-e', '--email email', 'Email of a zendesk agent having access to the help center (e.g. joe@icecream.com)') { |email|  options[:email] = email }
  opts.on('-p', '--password password', 'Password')  { |password|  options[:password] = password }
  opts.on('-d', '--subdomain subdomain', 'Zendesk subdomain (e.g. icecream)')  { |subdomain|  options[:subdomain] = subdomain}
  opts.on('-v', '--verbose-logging', 'Verbose logging to identify possible bugs')     { options[:log_level] = :verbose }
  opts.on('-c', '--compact-file-names', 'Force short filenames for windows based file systems that are limited to 260 path lengths') { options[:output_type] = :id_only }
  opts.on('-h', '--help', 'Displays Help') { puts opts; exit }
end.parse!

# run the class
export = ExportHelpCenter.new(options)
export.to_html!
export.to_json!
export.create_table_of_contents!
