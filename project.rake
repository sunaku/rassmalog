=begin
  Copyright 2006 Suraj N. Kurapati

  This file is part of Rassmalog.

  Rassmalog is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.

  Rassmalog is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Rassmalog; if not, write to the Free Software Foundation,
  Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
=end

require 'rake/clean'
require 'rake/rdoctask'
require 'rake/packagetask'


## project configuration

PROJECT_ID = :rassmalog
PROJECT_SSH_URL = "snk@rubyforge.org:/var/www/gforge-projects/#{PROJECT_ID}"

File.read('HISTORY') =~ /^=.*(\d\.\d.\d)/
PROJECT_VERSION = $1


task :default

desc "Generate release packages."
task :dist => [:clobber, :doc] do
  sh 'rake', '-f', __FILE__, 'package'
end

desc "Upload the project website."
task :web => :doc do |t|
  sh 'scp', '-Cr', 'doc', PROJECT_SSH_URL
end

desc 'Connect to website FTP.'
task :ftp do
  sh 'lftp', "sftp://#{PROJECT_SSH_URL}"
end


Rake::RDocTask.new :doc do |rd|
  rd.main = 'README'
  rd.rdoc_dir = 'doc'
  rd.rdoc_files.include 'README', 'HISTORY', 'config/*.rb'
end

Rake::PackageTask.new PROJECT_ID, PROJECT_VERSION do |p|
  p.need_tar_gz = true
  p.need_zip = true
  p.package_files.exclude('_darcs', __FILE__).include('**/*')
end