require 'rassmalog'

# definition of what should occur in order to generate your blog
task :gen => [ :copy, :entry, :entry_meta, :entry_list, :feed ]

feed 'rss.xml', NEW_ENTRIES, BLOG.name, BLOG.info
feed 'ann.xml', TAGS['history'], 'Rassmalog releases', 'Announcements about new Rassmalog releases', true
