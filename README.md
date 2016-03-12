#  Ruby script to export your Zendesk helpcenter

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
# Contribute

Feel free to contribute through a pull request. This code has only been tested on one zendesk account and only on mac.


# Credits

- thanks to https://github.com/skipjac/pull-zendesk-forums
- Author of this script: https://github.com/pjmuller
- License: MIT
