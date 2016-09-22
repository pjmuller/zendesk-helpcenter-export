#  Ruby script to export your Zendesk helpcenter (v 0.2)

Script based on https://github.com/skipjac/pull-zendesk-forums
(which exports the forum, not the help center article)

it uses the Zendesk API to export all categories, sections, articles, article_attachments to html (and json)
all of this in a nested folder structure

    - category
      - section
        - article
          - article.html
          - image-1.jpg
          - image-2.png
    meta_data.json

![Zendesk demo](https://github.com/pjmuller/zendesk-helpcenter-export/raw/master/demo-screenshot.png)
Bonus: it is smart in that when you rename a category, section, article it won't
start to create duplicate folders but renames the old ones.
The script can thus be used for both a new dump as updating an existing one.

# How to use?

1. have a machine with ruby and rubygems installed
(if you don't know how to do this, this script is probably out of your leage)

2. copy this .rb file to the place where you want to store the export
3. use terminal to navigate to the folder and run

        ruby zendesk-helpcenter-export.rb -e yourzenmail@domain.com -p YoUrPassWoRd -d my-zen-subdomain

Want some more info about parameters and options?

    ruby zendesk-helpcenter-export.rb  --help

# Extra options

While running the command you can pass two extra options

- ```ruby zendesk-helpcenter-export.rb ... --compact-file-names``` which will only use the category / section / article id and not the name in the folder and file names.

  You do not need to remove all directies and files if you switch from the longer (slugified) names to only id's. The script will smartly rename everything. Isn't that neat :)?
- ```ruby zendesk-helpcenter-export.rb ... --verbose-logging``` to help you debugging when something is not going as planned

- ```ruby zendesk-helpcenter-export.rb ... --filter-locales locales``` allow to export data for specified locales only

# Requirements

- ruby >= 2.0, do ```ruby -v``` in your terminal. If lower google how update. (easy with rvm, rbenv, brew)
- httparty gem, install through ```gem install httparty```

# FAQ
## I am getting LoadError's
When you get the error

    cannot load such file -- httparty (LoadError)

it means you don't have the httpnecessary gems installed. Try

    gem install httparty

to solve the problem. (the same solution can be applied to install other missing gems)

## I get "Could not connect to the Zendesk API" error
This is probably due to inserting an incorrect parameter

- ```-e``` put your zendesk agent emailaddress. One that has access to the helpcenter articles
- ```-p``` double check by logging out and in on [zendesk.com](http://zendesk.com) that you have the right password
- ```-d``` your zendesk subdomain. For example, if your agent interface is available under my-company.zendesk.com, your value is ```my-company``



# Known limitations
- we do not delete categories / sections / articles / attachments when they are deleted in Zendesk. Feel free to make a pull request to add this functionality (baiscally you'll have to compare ```raw_data``` array to the actual folders and files)
- in the update from ```v0.1``` to ```v0.2``` the html filenames changed to ```article-name.html```  to ```index.html```. The old html files are however not removed. You thus better remove everything and make a fresh export if you do not wish duplicate html files.

# Contribute

Feel free to contribute through a pull request. This code has only been tested on one zendesk account and only on mac.


# Credits

- thanks to https://github.com/skipjac/pull-zendesk-forums
- Author of this script: https://github.com/pjmuller
- License: MIT
