# This file defines the String#to_html method which is invoked to transform
# the content of an entry (the value of the string) into HTML.
#
# It features, in addition to the Textile formatting system (RedCloth) and
# syntax coloring (CodeRay), smart source code sizing (block vs. inline
# display) and table of contents generation.

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


  Heading = Struct.new :anchor, :title, :depth
  @@anchorNum = 0

  # Returns a table of contents (in RedCloth format) from the RedCloth text in this string *and* the text which it can link to.
  def table_of_contents
    headings = []
    text = self.dup

    # parse document structure and insert anchors (so that the table of contents can link directly to these headings) where necessary
      text.gsub! %r{^(\s*h(\d))(.*?[\}\)]?\.)(.*)$} do
        target = $~.dup

        title = target[4].strip
        depth = target[2].to_i

        hasAnchor = target[3] =~ /#(.*?)\)/
        anchor = $1 || "anchor#{@@anchorNum += 1}"

        headings << Heading.new(anchor, title, depth)

        if hasAnchor
          target.to_s
        else
          arrow =
            if target[3] =~ /^(.*)(\(.*?)(\).*)$/
              $1 + $2 + '#' + anchor + $3
            else
              '(#' + anchor + ')' + target[3]
            end

          target[1] + arrow + target[4]
        end
      end

    # generate table of contents
      toc = headings.map do |h|
        %{#{'*' * h.depth} "#{h.title}":##{h.anchor}}
      end.join("\n").redcloth

    [toc, text]
  end
end
