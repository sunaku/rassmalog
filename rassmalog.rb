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
require 'config/format'
require 'yaml'
require 'ostruct'
require 'date'

require 'erb'
include ERB::Util


class DateTime
  # Returns the RFC-822 representation, which is required by RSS, of this object.
  def rfc822
    strftime "%a, %d %b %Y %H:%M:%S %Z"
  end
end

class String
  # Transforms this string into a vaild file name that can be safely used in a URL.
  # see http://en.wikipedia.org/wiki/URI_scheme#Generic_syntax
  def to_file_name
    downcase.               # it's hard to remember capitalization in URLs
    gsub(/\s+/, '-').       # remove the need for %20 escapes in URLs
    gsub(%r{[/;?#]+}, '-'). # these are parts of a URL syntax
    squeeze('-')
  end

  # Transforms this UTF-8 string into HTML entities.
  def to_html_entities
    unpack('U*').map! {|c| "&##{c};"}.join
  end
end

class ERB
  # Renders this template within a fresh object configured by the given block.
  def render_with &aBlock
    dummy = Object.new
    dummy.instance_eval(&aBlock)
    result dummy.instance_eval {binding}
  end
end

# Something that can be (hyper)linked to.
# Objects that mix-in this module must define a #to_s method, whose value is used when determining the URL for this object.
module Linkable
  # Returns a relative URL to this page.
  def url
    to_s.to_file_name << '.html'
  end

  # Returns a relative hyperlink to this page.
  def to_link aName = name
    %{<a href="#{u url}">#{aName}</a>}
  end

  # Compares this page to the given page.
  def <=> aOther
    url <=> aOther.url
  end
end

class Language < OpenStruct
  # Translates the given string and then formats (see String#format) the translation with the given placeholder arguments. If the translation is not available, then the given string will be used instead.
  def [] aString, *aArgs
    (self.send(aString) || aString) % aArgs
  end
end


## data structures for organizing entries

# A single blog entry.
class Entry < OpenStruct
  include Linkable

  def url
    stamp = date.strftime "%F"
    "#{stamp}-#{name}.html".to_file_name
  end

  # Returns a URL for submiting comments about this entry.
  def comment_url
    addr = "mailto:#{BLOG.email}".to_html_entities
    subj = u "[Rassmalog] #{name}"
    body = u File.join(BLOG.url, url)

    "#{addr}?subject=#{subj}&amp;body=#{body}"
  end

  # Transforms this entry into HTML.
  # aSummarize:: Causes only the first paragraph of this entry's content to be included in the result.
  def to_html aSummarize = false
    old = text

    # summarize the entry body
      paras = text.split(/(?:\r?\n){2,}/m)

      if aSummarize
        self.text = "#{paras.first}\n\n#{to_link LANG["Read more..."]}"
      end

    # transform the entry into HTML
      entry = self
      html = ENTRY_TEMPLATE.render_with {@entry = entry}

    self.text = old
    html
  end

  # Renders a HTML page for this Entry.
  def render
    t, c = name, to_html
    HTML_TEMPLATE.render_with do
      @title, @content = t, c
    end
  end

  # Compares this entry to the given entry.
  # This is used to sort a list of entries by date.
  def <=> aOther
    date <=> aOther.date
  end
end

# A listing of blog entries (Entry objects).
class Page
  include Linkable

  attr_reader :name, :entries, :chapter

  # aName:: name of this page
  # aEntries:: Entry objects that belong in this page
  # aChapter:: Chapter object which contains this page
  def initialize aName, aEntries, aChapter
    @name = aName
    @entries = aEntries
    @chapter = aChapter
  end

  alias to_s name

  # Renders a HTML page for this Page.
  def render
    page = self

    HTML_TEMPLATE.render_with do
      @title = page.name
      @content = PAGE_TEMPLATE.render_with {@page = page}
    end
  end

  # Returns the next page in the chapter.
  def next
    sibling(+1)
  end

  # Returns the previous page in the chapter.
  def prev
    sibling(-1)
  end

  private

  def sibling aOffset
    list = chapter.pages
    pos = list.index(self)

    list[(pos + aOffset) % list.length]
  end
end

# A listing of pages (Page objects).
class Chapter
  include Linkable

  attr_reader :name, :pages

  # aName:: name of this Chapter
  # aHash:: mapping from Page name to array of Entry
  def initialize aName, aHash
    @fileName = aName
    @name = LANG[aName]
    @pages = []

    aHash.each_pair do |k, v|
      @pages << Page.new(k, v, self)
    end

    @pages.sort!
  end

  def to_s
    'index_' + @fileName.downcase
  end

  # Renders a HTML page for this Chapter.
  def render
    chapter = self

    HTML_TEMPLATE.render_with do
      @title = chapter.name
      @content = CHAPTER_TEMPLATE.render_with {@chapter = chapter}
    end
  end
end


# Notify the user about some action being performed.
def notify *args
  printf "%12s  %s\n", *args
end

# Loads the given YAML file into the given wrapper.
def load_yaml_file aFile, aWrapper = OpenStruct
  aWrapper.new(YAML.load_file(aFile))
end

# Writes the given content to the given file.
def write_file aPath, aContent
  File.open aPath, 'w' do |f|
    # lstrip because XML declaration must be at start of file
    f << aContent.lstrip
  end
end

# Returns the path of the output file.
def generate_html_task aPage, *aDeps #:nodoc:
  dst = File.join('output', aPage.url)

  file dst => aDeps.flatten + COMMON_DEPS do
    notify aPage.class, dst
    write_file dst, aPage.render
  end

  task :gen => dst
  CLOBBER.include dst

  dst
end

# Generates an index, which is not a fully qualified Page but behaves like one, of entries.
# NOTE: the aName parameter will be localized later by this method, so only provide English strings
def generate_special_index aName, aEntries, aMode, aFileName = nil #:nodoc:
  dst = aFileName || File.join('output', "index_#{aName.downcase}.html".to_file_name)

  file dst => ENTRY_FILES + COMMON_DEPS do
    index = HTML_TEMPLATE.render_with do
      @title = LANG[aName]
      @content = %{<h1>#{@title}</h1>} << aEntries.map {|e| e.to_html aMode}.join
    end

    notify aName, dst
    write_file dst, index
  end

  task :gen => dst
  CLOBBER.include dst
end


## input processing stage

# load blog configuration
  BLOG = load_yaml_file('config/blog.yaml')

  FileList['config/*.erb'].each do |f|
    name = File.basename(f, File.extname(f))
    var = "#{name.upcase}_TEMPLATE"

    Kernel.const_set var.to_sym, ERB.new(File.read(f))
  end

# load translations
  langFile = "config/lang/#{BLOG.language}.yaml"
  LANG = load_yaml_file(langFile, Language) rescue Language.new

# load blog entries
  ENTRY_FILES = FileList['entries/**/*.yaml']

  ENTRIES = ENTRY_FILES.map do |src|
    entry = load_yaml_file(src, Entry)
    entry.src_file = src
    entry.date = DateTime.parse(entry.date.to_s)
    entry.tags = entry.tags.to_a rescue [entry.tags]

    entry
  end.sort.reverse!

  # Returns the most recent entries
  def ENTRIES.recent
    self[0, BLOG.recent_entries || 0]
  end

  RECENT_ENTRY_FILES = ENTRIES.recent.map! {|e| e.src_file}

# organize blog entries into chapters
  tags = Hash.new {|h,k| h[k] = []}
  months = Hash.new {|h,k| h[k] = []}

  # parse tags and months from entries
    ENTRIES.each do |entry|
      entry.tags.each do |tag|
        tags[tag] << entry
      end.clear # will be restored later

      months[entry.date.strftime(BLOG.archive_frequency)] << entry
    end

  # organize entries into pages
    TAGS = Chapter.new('Tags', tags)
    ARCHIVES = Chapter.new('Archives', months)

    # restore tags for entry
      TAGS.pages.each do |tag|
        tag.entries.each do |entry|
          entry.tags << tag
        end
      end

      ARCHIVES.pages.each do |month|
        month.entries.each do |entry|
          entry.archive = month
        end
      end

  CHAPTERS = [TAGS, ARCHIVES]


## output generation stage

task :default => :gen

desc "Generate the blog."
task :gen

desc "Regenerate the blog from scratch."
task :regen => [:clobber, :gen]

CONFIG_FILES = FileList['config/**/*']
COMMON_DEPS = ['output'] + CONFIG_FILES

# create output directory
  directory 'output'
  CLOBBER.include 'output'

# copy everything from input/ into output/
  FileList['input/**/*'].each do |src|
    dst = src.sub('input', 'output')

    file dst => [src] + COMMON_DEPS do
      cp_r src, dst, :preserve => true
    end

    task :gen => dst
    CLEAN.include dst
  end

# generate HTML for blog entries
  ENTRIES.each do |entry|
    entry.dst_file = generate_html_task(entry, entry.src_file)
  end

# generate HTML for pages and chapters
  CHAPTERS.each do |chapter|
    generate_html_task chapter, ENTRY_FILES

    chapter.pages.each do |page|
      generate_html_task page, ENTRY_FILES
    end
  end

  generate_special_index "Search", ENTRIES, false
  generate_special_index "Entries", ENTRIES, true

# generate front page
  dst = 'output/index.html'

  if BLOG.front_page
    src = File.join('output', BLOG.front_page)

    file dst => [src] + COMMON_DEPS do
      notify 'front page', src
      cp src, dst, :preserve => true, :verbose => false
    end
  else
    generate_special_index "Recent entries", ENTRIES.recent, true, dst
  end

  task :gen => dst
  CLOBBER.include dst

# generate RSS feed
  file 'output/rss.xml' => ENTRY_FILES + COMMON_DEPS do |t|
    write_file t.name, RSS_TEMPLATE.result(binding)
    notify 'RSS feed', t.name
  end

  task :gen => 'output/rss.xml'
  CLOBBER.include 'output/rss.xml'


## output publishing stage

desc "Upload the blog to your website."
task :upload => [:gen, 'output'] do
  cmd = BLOG.uploader.split
  cmd.push 'output/', BLOG.host

  system(*cmd)
end