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

require 'yaml'
require 'erb'
require 'cgi'
require 'ostruct'
require 'date'

require 'config/format'


class String
  def to_file_name
    # file names cannot have slash
    gsub '/', '|'
  end
end

module NamedLink
  def url
    "#{to_s.to_file_name}.html"
  end

  def to_link
    "<a href=#{url.inspect}>#{self}</a>"
  end
end

class NamedLinkHash < Hash
  alias old_keys keys

  def keys
    old_keys.map! {|k| k.dup.extend NamedLink}
  end

  def each_pair
    keys.each do |k|
      yield k, self[k]
    end
  end

  # Renders, within the context of the given blog, a HTML page for the given key.
  def render aKey, aBlog
    entries = self[aKey]

    aBlog.instance_eval do
      @page_title = aKey.to_s.capitalize
      heading = "<h1>#{@page_title}</h1>\n\n"

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

def load_yaml_file aFile
  OpenStruct.new(YAML.load_file(aFile))
end


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
  @tags = NamedLinkHash.new {|h,k| h[k] = []}
  @archives = NamedLinkHash.new {|h,k| h[k] = []}

  @entries = FileList['entries/*.yml'].map do |src|
    entry = load_yaml_file(src)
    entry.src_file = src
    entry.date_obj = DateTime.parse entry.date
    entry.rss_date = entry.date_obj.strftime "%a, %d %b %Y %H:%M:%S %Z"
    entry.tags = entry.tags.to_a rescue [entry.tags]

    def entry.url
      "#{date_obj}-#{name}.html".to_file_name
    end

    def entry.to_link
      "<a href=#{url.inspect}>#{name}</a>"
    end

    def entry.to_html
      @entry = self
      ENTRY_TEMPLATE.result(binding).to_html
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
    entry.date_obj
  end.reverse!

  # this stuff is done *after* the entries have been sorted, so that stuff in the archives appears in the correct chronological order
  @entries.each do |entry|
    # determine which tags this entry belongs to
      entry.tags.each do |tag|
        tag.extend NamedLink
        @tags[tag] << entry
      end

    # determine which archive this entry belongs to
      date = entry.date_obj
      arch = "#{date.year}-#{date.month}"

      @archives[arch] << entry
  end

# generate pages for entries
  @entries.each do |entry|
    dst = File.join('output', entry.url)

    file dst => ['output', entry.src_file] do
      File.open dst, 'w' do |f|
        f << entry.render(self)
      end

      notify :entry, dst
    end

    task :default => dst
    CLEAN.include dst
  end

# generate archive pages for entries
  index = NamedLinkHash.new
  index['index'] = @entries[0, @blog.index]

  {
    :tag => @tags,
    :archive => @archives,
    :index => index,
  }.each_pair do |msg, h|
    h.keys.sort.each do |k|
      dst = File.join('output', k.url)

      file dst => ['output'] do
        File.open dst, 'w' do |f|
          f << h.render(k, self)
        end

        notify msg, dst
      end

      task :default => dst
      CLEAN.include dst
    end
  end

# generate RSS feed
  file 'output/rss.xml' => ['output'] do |t|
    File.open t.name, 'w' do |f|
      f << RSS_TEMPLATE.result(binding)
    end

    notify :rss, t.name
  end

  task :default => 'output/rss.xml'
  CLEAN.include 'output/rss.xml'


# generate output directory
  directory 'output'
  CLOBBER.include 'output'

  # copy everything from input/ into output/
    FileList['input/*'].each do |src|
      dst = "output/#{File.basename src}"

      file dst => ['output', src] do
        cp_r src, dst, :preserve => true
      end

      task :default => dst
    end

# generate API documentation
  Rake::RDocTask.new do |rd|
    rd.main = "README"
    rd.rdoc_dir = 'doc'
    rd.rdoc_files.include("README", "config/*.rb")
  end
