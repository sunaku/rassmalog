require 'rassmalog' # loads the core of Rassmalog; this is necessary!

#
# Activate additional plugins, which provide useful Rake tasks.
#
require 'plugins/new' # allows easy creation of blog entry source files
require 'plugins/import' # allows you to import blog entries from feeds

#
# Define what work must be performed to generate
# your blog (when you run the "rake gen" command).
#
# To see a description of the Rake tasks in the
# list below, please run the "rake -T" command.
#
task :gen => [ :copy, :entry, :entry_list, :entry_meta, :search, :feed ]

#
# The primary news feed for your blog.
#
# See the API documentation for the feed() method in the user guide for help.
#
feed 'feed.xml', ENTRIES.first(5), BLOG.name, BLOG.info

#
# Example of creating additional news feeds for your blog.
#
# This example creates a separate news feed containing
# the newest three blog entries tagged as 'tricks'.
#
feed(
  'examples.xml',                      # feed output file
  TAGS['examples'].first(3),           # which entries to include in feed?
  'Rassmalog examples',                # feed title
  'Examples of how to use Rassmalog.', # feed description
  true                                 # summarize the entries in the feed?
)

