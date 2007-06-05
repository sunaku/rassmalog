# This file defines the String#to_html method, which is invoked to
# transform the content of an entry (the value of the string) into HTML.
#
# It features the Textile formatting system (RedCloth), syntax coloring
# (CodeRay), and smart source code sizing (block vs. inline display).
#--
# Copyright 2006-2007 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'cgi'

begin
  require 'rubygems'
rescue LoadError
end

require 'coderay'
require 'redcloth'

class String
  # The content of these HTML tags will be preserved verbatim
  # when they are processed by Textile. By doing this, we
  # avoid unwanted Textile transformations, such as quotation
  # marks becoming curly (&#8192;), in source code.
  PRESERVED_TAGS = %w[tt code pre]

  # Transforms this string into HTML.
  def to_html
    text = dup

    # escape preserved tags
      preserved = {} # escaped => original

      PRESERVED_TAGS.each do |tag|
        text.gsub! %r{(<#{tag}.*?>)(.*?)(</#{tag}>)}m do
          orig = $1 + CGI.escapeHTML(CGI.unescapeHTML($2)) + $3
          esc  = orig.object_id.abs.to_s * 5

          preserved[esc] = orig
          esc
        end
      end

    # convert Textile into HTML
      html = text.redcloth

    # restore preserved tags
      preserved.each_pair do |esc, orig|
        html.gsub! %r{<p>#{esc}</p>|#{esc}}, orig
      end

    # fix annoyances in Textile conversion
      # redcloth wraps indented text within <pre> tags
      html.gsub! %r{(<pre>)\s*<code>(.*?)\s*</code>\s*(</pre>)}m, '\1\2\3'
      html.gsub! %r{(<pre>)\s*<pre>(.*?)</pre>\s*(</pre>)}m, '\1\2\3'

      # redcloth wraps a single item within paragraph tags, which
      # prevents the item's HTML from being validly injected within
      # other block-level elements, such as headings (h1, h2, etc.)
      html.sub! %r{^<p>(.*)</p>$}m do |match|
        payload = $1

        if payload =~ /<p>/
          match
        else
          payload
        end
      end

    html.coderay
  end

  # Returns the result of running this string through RedCloth.
  def redcloth
    RedCloth.new(self).to_html
  end

  # Adds syntax coloring to <code> elements in the given text. If the
  # <code> tag has an attribute lang="...", then that is considered the
  # programming language for which appropriate syntax coloring should be
  # applied. Otherwise, the programming language is assumed to be ruby.
  def coderay
    gsub %r{<(code)(.*?)>(.*?)</\1>}m do
      code = CGI.unescapeHTML $3
      atts = $2

      lang =
        if $2 =~ /lang=('|")(.*?)\1/i
          $2
        else
          :ruby
        end

      tag =
        if code =~ /\n/
          :pre
        else
          :code
        end

      html = CodeRay.scan(code, lang).html(:css => :style)

      %{<#{tag} class="code"#{atts}>#{html}</#{tag}>}
    end
  end
end
