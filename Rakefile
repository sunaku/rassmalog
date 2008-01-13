require 'rassmalog'

# definition of what should occur in order to generate your blog
task :gen => [ :copy, :entry, :entry_meta, :entry_list, :feed ]

# feed for new blog entries (see the feed() method in rassmalog.rb for details)
feed 'feed.xml', NEW_ENTRIES, BLOG.name, BLOG.info

# feed for rassmalog announcements
feed 'ann.xml', TAGS['history'][0,3], 'Rassmalog releases',
     'Announcements about new Rassmalog releases', true
