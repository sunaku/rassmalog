require 'rassmalog'

# definition of what should happen to generate your blog
# run "rake -T" to see a description of these tasks
task :gen => [ :copy, :entry, :entry_meta, :entry_list, :feed ]

# feed for new blog entries (see the feed() method in the user guide for help)
feed 'feed.xml', NEW_ENTRIES, BLOG.name, BLOG.info

# feed for rassmalog announcements
feed 'ann.xml', TAGS['history'][0,3], 'Rassmalog releases',
     'Announcements about new Rassmalog releases', true

# plug-ins that provide additional Rake tasks
require 'plugins/import' # allows you to import blog entries from feeds
