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


# load the blog.yml configuration file
  class OpenStruct
    # remove b/c rake hijacks this method!
    # thus, we are unable to access @blog.link
    undef_method :link
  end

  @blog = OpenStruct.new(YAML.load_file('config/blog.yml'))

# load ERB templates
  FileList['config/*.erb'].each do |f|
    name = File.basename(f, File.extname(f))
    var = "#{name.upcase}_TEMPLATE"

    Kernel.const_set var.to_sym, ERB.new(File.read(f))
  end

# parse blog entries
  @tags = Hash.new {|h,k| h[k] = []}
  @archives = Hash.new {|h,k| h[k] = []}

  [@tags, @archives].each do |h|
    class << h
      alias old_keys keys

      def keys
        old_keys.map! {|k| k.dup.extend NamedLink}
      end
    end
  end

  @entries = FileList['entries/*.yml'].map do |src|
    entry = OpenStruct.new YAML.load_file(src)
    entry.src_file = src
    entry.date_obj = DateTime.parse entry.date
    entry.rss_date = entry.date_obj.strftime "%a, %d %b %Y %H:%M:%S %Z"

    def entry.url
      "#{date_obj}-#{name}.html".to_file_name
    end

    def entry.to_link
      "<a href=#{url.inspect}>#{name}</a>"
    end

    # determine which tags this entry belongs to
      tags = entry.tags
      tags = [tags] unless tags.respond_to? :each

      tags.each do |tag|
        tag.extend NamedLink
        @tags[tag] << entry
      end

    # determine which archive this entry belongs to
      date = entry.date_obj
      arch = "#{date.year}-#{date.month}"

      @archives[arch] << entry

    entry
  end

# generate blog output
  @entries.each do |entry|
    date = DateTime.parse entry.date
    name = entry.name.to_file_name
    dst = File.join('output', "#{date}-#{name}") << '.html'

    file dst => ['output', entry.src_file] do
      @entry = entry
      entryOutput = ENTRY_TEMPLATE.result(binding).to_html

      @content = entryOutput
      pageOutput = HTML_TEMPLATE.result(binding)

      File.open dst, 'w' do |f|
        f << pageOutput
      end

      puts dst
    end

    task :default => dst
    CLEAN.include dst
  end


directory 'output'
CLOBBER.include 'output'
