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
    @raw_data = {locales: [], categories: [], sections: [], articles: [], article_attachments: []}
    # configure Httparty base uri
    self.class.base_uri "https://#{options[:subdomain]}.zendesk.com"
  end

  # section: loop over all categories, sections, articles and attachments
  # ---------------------------------------

  def to_html!
    locales["locales"].each do |locale_code|
      # contrary to what is said on https://developer.zendesk.com/rest_api/docs/core/locales
      # we do not get an ID, so I'm inventing one that is unique per locale
      locale = {"name" => locale_code, "id" => locale_code.chars.map {|ch| ch.ord - 'A'.ord + 10}.join}
      @raw_data[:locales] << locale

      categories(locale_code)['categories'].each do |category|
        log(category['name'].upcase)
        @raw_data[:categories] << category

        sections(locale_code, category['id'])['sections'].each do |section|
          @raw_data[:sections] << section
          log("  #{section['name']}")

          articles(locale_code, section['id'])['articles'].each do |article|
            log("    #{article['name']}", :standard)

            article_dir = dir_path(locale, category, section, article)
            file_path = "#{article_dir}index.html"
            article['backup_path'] = file_path
            @raw_data[:articles] << article

            File.open(file_path, "w+") { |f| f.puts article_html_content(article) }

            article_attachments(article['id'])['article_attachments'].each do |article_attachment|
              @raw_data[:article_attachments] << article_attachment
              # optimization, do not download attachment when already present (we could check based on the id)
              download_attachment!(article_attachment, article_dir)
            end
          end
        end
      end
    end
  end

  # can only be called AFTER export_html_and_images!
  def to_json!
    File.open("./meta_data.json", "w+") { |f| f.puts JSON.pretty_generate(raw_data) }
  end

  def create_table_of_contents!
    File.open("./index.html", "w+") { |f| f.puts main_overview_file }
  end

  # Section: Article content
  # ---------------------------------------

  def article_html_content(article)
    # add some boilerplat to make it all look nicer
    # and replace all image links towards the local url
    regex_find = /https:\/\/.+?zendesk.com.+?article_attachments\/(\d+?)\/(.+)\.(.+?)" alt/
    regex_replace = output_type == :slugified ? '\1-\2.\3" alt' : '\1.\3" alt'
    boiler_plate_html do
      """
      <h1>#{article['name']}</h1>
      #{article['body'].to_s.gsub(regex_find, regex_replace)}
      """
    end
  end

  def main_overview_file
    boiler_plate_html do
      content = []

      raw_data[:locales].each do |locale|
        content << "<h1>#{locale['name']}</h1>"
        raw_data[:categories].each do |cat|
          content << "<h2>#{cat['name']}</h2>"
          raw_data[:sections].each do |section|
            next if section["category_id"] != cat['id']
            content << "<span class=\"wysiwyg-font-size-large\">#{section["name"]}</span><br />"
            content << "<ul>"
            raw_data[:articles].each do |article|
              next if article["section_id"] != section['id']
              content << "<li><a href='#{article['backup_path']}'>#{article['name']}</a></li>"
            end
            content << "</ul>"
          end
        end
      end
      content.join("\n")
    end
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
  def dir_path(locale, category, section = nil, article = nil)
    # each resource has an id and name attribute
    # let's use this to build a path where we can store the actual data
    log("      buidling dir_path for #{[locale, category, section, article].compact.map{|r| r['name']}}", :verbose)
    [locale, category, section, article].compact.inject("./") do |dir_path, resource|
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
    response = self.class.get("/api/v2/help_center/#{url}", options)
    return_response_or_exit_when_error(response)
  end

  def return_response_or_exit_when_error(api_response)
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

      exit
    else
      api_response
    end
  end


  # see documentation on https://developer.zendesk.com/rest_api/docs/help_center/introduction
  def locales()                         api("locales.json")                                       end
  def categories(locale)                api("#{locale}/categories.json")                          end
  def sections(locale, category_id)     api("#{locale}/categories/#{category_id}/sections.json")  end
  def articles(locale, section_id)      api("#{locale}/sections/#{section_id}/articles.json")     end
  def article_attachments(article_id)   api("articles/#{article_id}/attachments.json")            end


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
