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

ERB_CONTEXT = self


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
    gsub(%r{[/;?#]+}, '+'). # parts of a URL syntax
    gsub(/\s+/, '-')        # removes need for %20 escapes
  end
end


## data structures for organizing entries

Page = Struct.new :name, :url

# Represents a generated HTML page, which is associated with a list of entries. This association is maintained by the Chapter class.
class Page
  alias old_url url

  # Returns a relative URL to this page.
  def url
    (old_url || name).to_s.to_file_name << '.html'
  end

  # Returns a relative hyperlink to this page.
  def to_link aName = name
    %{<a href="#{u url}">#{aName}</a>}
  end

  # Compares this page to the given page.
  def <=> aOther
    url <=> aOther.url
  end

  alias to_s name
end

# A mapping from a Page to its entries.
class Chapter < Hash
  attr_reader :name

  # aName:: name of this chapter
  # the rest:: arguments to Hash.new
  def initialize aName, *aArgs, &aBlock
    @name = aName
    super *aArgs, &aBlock
  end

  alias pages keys

  # Renders, within the context of the given blog, the given page into HTML.
  def render aPage
    entries = self[aPage]
    title = "#{name} &mdash; #{aPage.name}"

    ERB_CONTEXT.instance_eval do
      @page_title = title
      heading = "<h2>#{@page_title}</h2>\n\n"

      @page_content = entries.inject heading do |memo, entry|
        memo << entry.to_html(true)
      end

      HTML_TEMPLATE.result(binding)
    end
  end
end

module Entry
  # Returns the name of the generated HTML file.
  def url
    stamp = date.strftime "%F"
    "#{stamp}-#{name}.html".to_file_name
  end

  # Returns a hyperlink to the generated HTML file.
  def to_link aName = name
    %{<a href="#{u url}">#{aName}</a>}
  end

  # Transforms this entry into HTML (for the generated HTML file).
  def to_html aSummarize = false
    old = text

    # summarize the entry body
      if aSummarize and text =~ /^.*?(\r?\n){2,}/m
        link = to_link "Continue reading <big>&rarr;</big>"
        self.text = $& << link
      end

    # transform the entry into HTML
      @entry = self
      html = ENTRY_TEMPLATE.result binding

    self.text = old
    html
  end

  # Renders, within the context of the given blog, a HTML page for this entry.
  def render
    t, c = name, to_html
    ERB_CONTEXT.instance_eval do
      @page_title = t
      @page_content = c
      HTML_TEMPLATE.result binding
    end
  end

  # Compares this entry to the given entry.
  def <=> aOther
    date <=> aOther.date
  end
end


# Notify the user about some action being performed.
def notify *args
  printf "%8s  %s\n", *args
end

# Loads the given YAML file into an OpenStruct.
def load_yaml_file aFile
  OpenStruct.new(YAML.load_file(aFile))
end

# Writes the given content to the given file.
def write_file aPath, aContent
  File.open aPath, 'w' do |f|
    # lstrip because XML declaration must be at start of file
    f << aContent.lstrip
  end
end


## input processing stage

# load blog configuration
  @blog = load_yaml_file('config/blog.yaml')

  FileList['config/*.erb'].each do |f|
    name = File.basename(f, File.extname(f))
    var = "#{name.upcase}_TEMPLATE"

    Kernel.const_set var.to_sym, ERB.new(File.read(f))
  end

# load blog entries
  ENTRY_FILES = FileList['entries/**/*.{yml,yaml}']

  @entries = ENTRY_FILES.map do |src|
    entry = load_yaml_file(src)
    entry.src_file = src
    entry.date = DateTime.parse(entry.date.to_s)
    entry.tags = entry.tags.to_a rescue [entry.tags]
    entry.extend Entry

    entry
  end.sort.reverse!

# organize blog entries into chapters
  @tags = Chapter.new("Tags") {|h,k| h[k] = []}
  @archives = Chapter.new("Archives") {|h,k| h[k] = []}

  # this stuff is done *after* the entries have been sorted, so that stuff in the archives appears in the correct chronological order
  @entries.each do |entry|
    # determine which tags this entry belongs to
      entry.tags.map! do |tag|
        page = Page.new tag
        @tags[page] << entry

        page
      end

    # determine which archive this entry belongs to
      arch = Page.new entry.date.strftime("%B %Y"), entry.date.strftime("%Y-%m")

      @archives[arch] << entry
  end

  @chapters = [@tags, @archives]


## output generation stage

desc "Generate the blog."
task :blog
task :default => :blog

CONFIG_FILES = FileList['config/*']

# generate output directory
  directory 'output'
  CLOBBER.include 'output'

  # copy everything from input/ into output/
    FileList['input/**/*'].each do |src|
      dst = "output/#{File.basename src}"

      file dst => [src, 'output'] do
        cp_r src, dst, :preserve => true
      end

      task :blog => dst
      CLEAN.include dst
    end

# generate pages for entries
  @entries.each do |entry|
    dst = entry.dst_file = File.join('output', entry.url)

    file dst => [entry.src_file, 'output'] + CONFIG_FILES do
      write_file dst, entry.render
      notify :entry, dst
    end

    task :blog => dst
    CLOBBER.include dst
  end

# generate archive pages for entries
  index = Chapter.new 'Index'
  index[Page.new('newest entries', 'index')] = @entries[0, @blog.index]

  (@chapters + [index]).each do |chapter|
    chapter.each_pair do |page, entries|
      dst = File.join('output', page.url)
      deps = entries.map {|e| e.dst_file} << 'output'

      file dst => deps do
        write_file dst, chapter.render(page)
        notify chapter.name, dst
      end

      task :blog => dst
      CLOBBER.include dst
    end
  end

# generate RSS feed
  file 'output/rss.xml' => ['output'] + CONFIG_FILES + ENTRY_FILES do |t|
    write_file t.name, RSS_TEMPLATE.result(binding)
    notify :rss, t.name
  end

  task :blog => 'output/rss.xml'
  CLOBBER.include 'output/rss.xml'


## output publishing stage

desc "Upload the blog to your website."
task :publish => [:blog, 'output'] do
  cmd = %w[rsync --rsh=ssh --archive --compress --update --progress]
  args = ['output/', @blog.host]

  system *(cmd + args)
end
