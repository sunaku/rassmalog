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

# This file contains the logic for generating the blog. It is designed to be
# embedded inside the main Rakefile in the parent directory because all
# paths in this file are relative to the parent directory.

require 'rake/clean'

require 'yaml'
require 'erb'
include ERB::Util
require 'ostruct'
require 'date'

require 'config/format'


class DateTime
  # Returns the RFC-822 representation, which is required by RSS, of this object.
  def rfc822
    strftime "%a, %d %b %Y %H:%M:%S %Z"
  end
end

class String
  def to_file_name
    # file names cannot have slash
    gsub '/', '|'
  end
end


## data structures for organizing entries

# Holds information about a "page", which is a collection of entries.
Page = Struct.new :name, :url
class Page
  alias old_url url

  def url
    (old_url || name).to_s.to_file_name << '.html'
  end

  def to_link
    "<a href=#{url.inspect}>#{name}</a>"
  end

  def <=> aOther
    name <=> aOther.name
  end
end

# A mapping from a Page to its entries.
class Chapter < Hash
  attr_reader :name

  def initialize aName, *aArgs, &aBlock
    @name = aName
    super *aArgs, &aBlock
  end

  alias pages keys

  # Renders, within the context of the given blog, the given page into HTML.
  def render aPage, aBlog
    entries = self[aPage]
    title = "#{name}: #{aPage.name}"

    aBlog.instance_eval do
      @page_title = title
      heading = "<h2>#{@page_title}</h2>\n\n"

      @page_content = entries.inject heading do |memo, entry|
        memo << entry.to_html
      end

      HTML_TEMPLATE.result(binding)
    end
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


## input processing stage

# load blog configuration
  class OpenStruct
    # remove b/c rake hijacks this method!
    # thus, we are unable to access @blog.link
    undef_method :link
  end

  @blog = load_yaml_file('config/blog.yml')

  FileList['config/*.erb'].each do |f|
    name = File.basename(f, File.extname(f))
    var = "#{name.upcase}_TEMPLATE"

    Kernel.const_set var.to_sym, ERB.new(File.read(f))
  end

# load blog entries
  @entries = FileList['entries/**/*.{yml,yaml}'].map do |src|
    entry = load_yaml_file(src)
    entry.src_file = src
    entry.date = DateTime.parse(entry.date.to_s)
    entry.tags = entry.tags.to_a rescue [entry.tags]

    # Returns the name of the generated HTML file.
    def entry.url
      stamp = date.strftime "%F"
      "#{stamp}-#{name}.html".to_file_name
    end

    # Returns a hyperlink to the generated HTML file.
    def entry.to_link
      "<a href=#{url.inspect}>#{name}</a>"
    end

    # Transforms this entry into HTML (for the generated HTML file).
    def entry.to_html
      @entry = self
      ENTRY_TEMPLATE.result binding
    end

    # Renders, within the context of the given blog, a HTML page for this entry.
    def entry.render aBlog
      t, c = name, to_html
      aBlog.instance_eval do
        @page_title = t
        @page_content = c
        HTML_TEMPLATE.result binding
      end
    end

    entry
  end.sort_by do |entry|
    entry.date
  end.reverse!

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

COMMMON_DEPS = FileList['config/*', 'output']

# generate output directory
  directory 'output'
  CLOBBER.include 'output'

  # copy everything from input/ into output/
    FileList['input/*'].each do |src|
      dst = "output/#{File.basename src}"

      file dst => [src, 'output'] do
        cp_r src, dst, :preserve => true
      end

      task :blog => dst
    end

# generate pages for entries
  @entries.each do |entry|
    dst = entry.dst_file = File.join('output', entry.url)

    file dst => [entry.src_file, *COMMMON_DEPS] do
      File.open dst, 'w' do |f|
        f << entry.render(self)
      end

      notify :entry, dst
    end

    task :blog => dst
    CLEAN.include dst
  end

# generate archive pages for entries
  index = Chapter.new 'Index'
  index[Page.new('Newest entries', 'index')] = @entries[0, @blog.index]

  (@chapters + [index]).each do |chapter|
    chapter.each_pair do |page, entries|
      dst = File.join('output', page.url)
      deps = entries.map {|e| e.dst_file} << 'output'

      file dst => deps do
        File.open dst, 'w' do |f|
          # lstrip because XML declaration must be at start of file
          f << chapter.render(page, self).lstrip
        end

        notify chapter.name, dst
      end

      task :blog => dst
      CLEAN.include dst
    end
  end

# generate RSS feed
  file 'output/rss.xml' => COMMMON_DEPS do |t|
    File.open t.name, 'w' do |f|
      # lstrip because XML declaration must be at start of file
      f << RSS_TEMPLATE.result(binding).lstrip
    end

    notify :rss, t.name
  end

  task :blog => 'output/rss.xml'
  CLEAN.include 'output/rss.xml'
