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

Bonus: it is smart in that when you rename a category, section, article it won't
start to create duplicate folders but renames the old ones.
The script can thus be used for both a new dump as updating an existing one.

# How to use?

1. have a machine with ruby and rubygems installed
(if you don't know how to do this, this script is probably out of your leage)

2. copy this .rb file to the place where you want to store the export
3. use terminal to navigate to the folder and run

        ruby zendesk-helpcenter-export.rb yourzenmail@domain.com YoUrPassWoRd my-zen-subdomain

# Contribute

Feel free to contribute through a pull request. This code has only been tested on one zendesk account and only on mac.


# Credits

- thanks to https://github.com/skipjac/pull-zendesk-forums
- Author of this script: https://github.com/pjmuller
- License: MIT
