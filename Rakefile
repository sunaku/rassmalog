require 'rassmalog'

# definition of what should occur in order to generate your blog
task :gen => [ :copy, :entry, :entry_meta, :entry_list, :feed ]

# feed for new blog entries
feed 'new.xml', NEW_ENTRIES, BLOG.name, BLOG.info

# feed for rassmalog announcements
feed 'ann.xml',
  TAGS['history'][0,3],                         # list of entries to put in feed
  'Rassmalog releases',                         # title of the feed
  'Announcements about new Rassmalog releases', # description of the feed
  true                                          # summarize the entry content?
