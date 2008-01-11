require 'rassmalog'

desc "Generate the blog."
task :default => [:copy, :entry, :entry_meta, :entry_list, :feed]

feed 'rss.xml', NEW_ENTRIES, BLOG.name, BLOG.info
feed 'ann.xml', TAGS['history'], 'Rassmalog releases', 'Announcements about new Rassmalog releases', true
