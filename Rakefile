require 'rassmalog'

desc "Generate the blog."
task :default => [:copy, :entry, :entry_meta, :entry_list, :feed]

desc "Copy files from input/ into output/"
task :copy

desc "Generate HTML for blog entries."
task :entry

desc "Generate HTML for tags and archives."
task :entry_meta

desc "Generate HTML for recent/all entry lists."
task :entry_list

desc "Generate RSS feeds for the blog."
task :feed

desc "Regenerate the blog from scratch."
task :regen => [:clobber, :default]

feed 'rss.xml', RECENT_ENTRIES, BLOG.name, BLOG.info
feed 'ann.xml', TAGS['history'], 'Rassmalog release announcements'
