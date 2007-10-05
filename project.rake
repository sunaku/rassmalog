# Copyright 2006-2007 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'
require 'rake/rdoctask'
require 'rake/packagetask'


## project configuration

PROJECT_ID = :rassmalog
PROJECT_SSH_URL = "snk@rubyforge.org:/var/www/gforge-projects/#{PROJECT_ID}"

if Dir['input/rassmalog/history/*'].sort.last =~ /\d+\.\d+\.\d+/
  PROJECT_VERSION = $&
else
  raise "could not parse project version"
end


task :default

desc "Generate release packages."
task :release => [:clobber, :rdoc, 'output'] do
  sh 'rake', '-f', __FILE__, 'package'
end

desc "Upload the project homepage."
task :web => [:rdoc, 'input', 'output'] do |t|
  sh 'rsync', '-avz', '--delete', 'ref', 'input', 'output', PROJECT_SSH_URL
end

desc 'Connect to website FTP.'
task :ftp do
  sh 'lftp', "sftp://#{PROJECT_SSH_URL}"
end

file 'output' do
  sh 'rake'
end

Rake::RDocTask.new do |rd|
  rd.rdoc_files.exclude('_darcs', 'pkg').include('**/*.rb')
  rd.rdoc_dir = 'ref'
end

Rake::PackageTask.new PROJECT_ID, PROJECT_VERSION do |p|
  p.need_tar_gz = true
  p.need_zip = true
  p.package_files.exclude('_darcs', File.basename(__FILE__)).include('**/*')
end

desc 'Generate release announcement.'
task :ann => 'output' do |t|
  system "w3m -T text/html -dump -cols 60 output/rassmalog/history/#{PROJECT_VERSION}.html"
end


TRANSLATE_DIR = 'translate-output'
directory TRANSLATE_DIR

def translate_string aString, aLang
  IO.popen("translate-bin -f en -t #{aLang}", 'r+') do |pipe|
    pipe.write aString
    pipe.close_write
    pipe.read
  end
end

desc 'Generate translation files.'
task :translate => TRANSLATE_DIR do
  # get list of strings to translate
    inputStrings = []

    FileList['*.rb', 'config/*.*'].each do |file|
      strings = File.read(file).scan(/LANG\[(.*?)\]/).flatten.map! {|s| eval(s)}
      inputStrings.concat(strings)
    end

    inputStrings.uniq!
    inputStrings.sort!

  `translate-bin -l | grep '^en.*text'`.split(/$/).each do |line|
    if line =~ /->\s+(\S+)\s+([^:]+):/
      lang, desc = $1, $2
      p lang => desc

      File.open(File.join(TRANSLATE_DIR, lang + '.yaml'), 'w') do |f|
        f.puts "# #{lang} #{desc}"

        inputStrings.each do |query|
          result = translate_string(query, lang)
          break if result.empty?

          p query => result
          f.puts "#{query}: #{result}"
        end
      end
    end
  end
end
