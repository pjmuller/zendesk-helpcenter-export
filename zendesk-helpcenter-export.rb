require 'rubygems'
require 'httparty'
require 'FileUtils'
require 'json'
require 'uri'


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
#     ruby zendesk-helpcenter-export.rb yourzenmail@domain.com YoUrPassWoRd my-zen-subdomain
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
  attr :raw_data

  include HTTParty
  headers 'content-type'  => 'application/json'

  def initialize(email_user:, password:, zedesk_subdomain:)
    @auth = {:username => email_user, :password => password}
    # used to make one big dumpfile of all metadata related to your helpcenter
    @raw_data = {categories: [], sections: [], articles: [], article_attachments: []}
    self.class.base_uri "https://#{zedesk_subdomain}.zendesk.com"
  end

  # section: loop over all categories, sections, articles and attachments
  # ---------------------------------------

  def to_html!
    categories['categories'].each do |category|
      puts category['name'].upcase
      @raw_data[:categories] << category

      sections(category['id'])['sections'].each do |section|
        @raw_data[:sections] << section
        puts "  #{section['name']}"

        articles(section['id'])['articles'].each do |article|
          @raw_data[:articles] << article
          puts "    #{article['name']}"

          article_dir = "#{dir_path(category, section, article)}/"
          # puts "article_dir = #{article_dir}"
          file_path = "#{article_dir}#{article['name']}.html"
          File.open(file_path, "w+") { |f| f.puts article_html_content(article, ) }

          article_attachments(article['id'])['article_attachments'].each do |article_attachment|
            @raw_data[:article_attachments] << article_attachment
            # optimization, do not download attachment when already present (we could check based on the id)
            download_attachment!(article_attachment, article_dir)
          end
        end
      end
    end
  end

  # can only be called AFTER export_html_and_images!
  def to_json!
    File.open("./meta_data.json", "w+") { |f| f.puts JSON.pretty_generate(raw_data) }
  end

  # section: Make sure directories exist
  # ---------------------------------------

  def article_html_content(article)
    regex_find = /https:\/\/.+?zendesk.com.+?article_attachments\/(\d+?)\/(.+?)" alt/
    regex_replace = '\1-\2" alt'
    # add some boilerplat to make it all look nicer
    # and replace all image links towards the local url
    """
<html>
  <head>
    <meta charset='UTF-8'>
    <link rel='stylesheet' href='http://output.jsbin.com/gefofo.css' />
  </head>
  <body>
    <div id='container'>
      <h1>#{article['name']}</h1>
      #{article['body'].gsub(regex_find, regex_replace)}
    </div>
  </body>
</html>
    """

  end

  # section: Make sure directories exist
  # ---------------------------------------

  # return the dir_path (string) for given resource
  # and create the path if does not exist yet
  def dir_path(category, section = nil, article = nil)
    # each resource has an id and name attribute
    # let's use this to build a path where we can store the actual data
    [category, section, article].compact.inject("./") do |dir_path, resource|
      # check if we have existing folder that needs to be renamed
      rename_dir_with_same_id!(dir_path, resource['id'], resource['name'])
      # build path and check if folder exists
      dir_path += "#{resource['id']}-#{slugify(resource['name'])}/"
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
  def rename_dir_with_same_id!(path, id, name)
    dir_to_rename = Dir.entries(path).select do |entry|
      dir_id,*slugified_name = entry.split("-")

      File.directory?(File.join(path,entry)) &&
        !(entry =='.' || entry == '..') &&
        dir_id == id.to_s &&
        slugified_name != slugify(name).split("-")
    end.first

    return false unless dir_to_rename

    puts "      renaming #{path}#{dir_to_rename} to  #{path}#{id}-#{slugify(name)}"
    FileUtils.mv "#{path}#{dir_to_rename}", "#{path}#{id}-#{slugify(name)}"
    return true
  end

  def slugify(text)
    text.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
  end

  # section: API calls
  # ---------------------------------------
  def api(url)
    options = {:basic_auth => @auth}
    self.class.get("/api/v2/help_center/#{url}", options)
  end

  # see documentation on https://developer.zendesk.com/rest_api/docs/help_center/introduction
  def categories()          api("categories.json")                          end
  def sections(category_id) api("categories/#{category_id}/sections.json")  end
  def articles(section_id)  api("sections/#{section_id}/articles.json")     end
  def article_attachments(article_id)  api("articles/#{article_id}/attachments.json") end


  def download_attachment!(article_attachment, store_in_dir)
    # check if file with that id is already present, if so, skip
    return true if Dir.entries(store_in_dir).select{|e| e.start_with?(article_attachment['id'].to_s)}.length > 0
    puts "      #{article_attachment['file_name']}"

    begin
      options = {:basic_auth => @auth}
      file_contents = self.class.get(article_attachment['content_url'], options)
      file_path = "#{store_in_dir}#{article_attachment['id']}-#{article_attachment['file_name']}"
      File.open(file_path, "w+") { |f| f.puts file_contents }
    rescue
      puts "failed download: " + file_content_url
    end
  end
end

# run the class
export = ExportHelpCenter.new(
  email_user: ARGV[0],
  password: ARGV[1],
  zedesk_subdomain: ARGV[2]
)

export.to_html!
export.to_json!
