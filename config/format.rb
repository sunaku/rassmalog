# This file defines the String#to_html method which is invoked to transform
# the content of an entry (the value of the string) into HTML.
#
# It features, in addition to the Textile formatting system (RedCloth) and
# syntax coloring (CodeRay), smart source code sizing (block vs. inline
# display) and automatic table of contents generation.
#
# It requires the following software to operate:
#
# * RedCloth[http://whytheluckystiff.net/ruby/redcloth/]
#
# * CodeRay[http://coderay.rubychan.de/]
#
# If you have RubyGems[http://rubygems.org/] on your system, then you can
# install the above requirements by running the following command:
#
#   gem install redcloth coderay
#

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

require 'cgi'

begin
  require 'rubygems'
rescue LoadError
end

require 'coderay'
require 'redcloth'

class String
  # Transforms this string into HTML.
  def to_html
    redcloth.coderay
  end

  # Returns the result of running this string through RedCloth.
  def redcloth
    RedCloth.new(self).to_html
  end

  # Adds syntax coloring to <code>...</code> elements in the given text. If
  # the <code> tag has an attribute lang="...", then that is considered the
  # programming language for which appropriate syntax coloring should be
  # applied. Otherwise, the programming language is assumed to be ruby.
  def coderay
    gsub %r{<(code)(.*?)>(.*?)</\1>}m do
      code = $3.unescape_html
      atts = $2

      lang =
        if $2 =~ /lang=('|")(.*?)\1/i
          $2
        else
          :ruby
        end

      type =
        if code =~ /\n/
          :pre
        else
          :code
        end

      html = CodeRay.scan(code, lang).html(:css => :style)

      %{<#{type} class="code"#{atts}>#{html}</#{type}>}
    end
  end

  def escape_html
    CGI.escapeHTML self
  end

  def unescape_html
    CGI.unescapeHTML self
  end
end
