# Copyright 2006 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'
require 'rake/rdoctask'
require 'rake/packagetask'


# project configuration
require 'version'

PROJECT_ID = :rassmalog
PROJECT_SSH_URL = File.expand_path("~/www/lib/#{PROJECT_ID}")
PROJECT_VERSION = Rassmalog[:version]


desc "Show a list of available tasks."
task :default do
  Rake.application.options.show_task_pattern = //
  Rake.application.display_tasks_and_comments
end

desc "Generate release packages."
task :dist => [:clobber, :doc, 'ref', 'output'] do
  sh 'rake', '-f', __FILE__, 'package'
end

desc "Generate documentation."
task :doc => 'doc/guide.html'

desc "Format the user guide."
file 'doc/guide.html' => 'doc/guide.erb' do |t|
  sh "erbook -u html #{t.prerequisites} > #{t.name}"
end
CLOBBER.include 'doc/guide.html'

desc "Upload the project homepage."
task :upload => ['doc', 'ref', 'output'] do |t|
  args = t.prerequisites + [PROJECT_SSH_URL]
  sh 'rsync', '-avz', '--delete', *args
end

file 'output' do
  sh 'rake'
end
CLOBBER.include 'output'

Rake::RDocTask.new 'ref' do |t|
  t.rdoc_files.exclude('_darcs', 'pkg').include('**/*.rb')
  t.rdoc_dir = t.name
end

Rake::PackageTask.new PROJECT_ID, PROJECT_VERSION do |p|
  p.need_tar_gz = true
  p.need_zip = true
  p.package_files.exclude('_darcs', File.basename(__FILE__)).include('**/*')
end


TRANSLATE_DIR = 'translate-output'
directory TRANSLATE_DIR

require 'open-uri'
require 'net/http'
require 'uri'

require 'rubygems'
require 'hpricot'

BABEL_FISH = URI.parse('http://babelfish.yahoo.com/translate_txt')

# Returns a list of possible languages available for translation:
#
#   [ [command, lang, name]... ]
#
def possible_languages
  open(BABEL_FISH).read.scan(/value="(en_(\w+))">.*?to\s*(.*?)</)
end

# Returns the translation of the given input using the given command.
def translate_string aInput, aCommand
  res = Net::HTTP.post_form BABEL_FISH,
    :eo => 'utf-8', :lp => aCommand, :trtext => aInput

  doc = Hpricot(res.body)
  (doc / '#result' / 'div').inner_html
end

desc 'Generate translation files.'
task :translate => TRANSLATE_DIR do
  # get list of strings to translate
  phrases = []

  FileList['*.rb', 'config/*.*', 'input/*.yaml'].each do |file|
    phrases.concat \
      File.read(file).scan(/LANG\[\s*(\S)(.*?)(\1)/).map {|s| eval(s.join) }
  end

  phrases.uniq!
  phrases.sort!
  puts phrases

  # translate the input strings
  possible_languages.each do |cmd, lang, desc|
    p lang => desc

    File.open(File.join(TRANSLATE_DIR, lang + '.yaml'), 'w') do |f|
      f.puts "# #{lang} - #{desc}"

      results =
        translate_string(phrases.join("\n\n\n"), cmd).

        # restore printf() tokens that were mangled in translation
        gsub(/%\s+s/, '%s').

        # no need for unicode ellipsis since RedCloth converts them
        gsub(/\342\200\246/, '...').

        strip.split(/$\s*/)

      phrases.zip(results).each do |src, dst|
        p src => dst
        f.puts "#{src}: #{dst}"
      end
    end
  end
end
