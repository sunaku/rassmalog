# This file is the core of Rassmalog.
#--
# Copyright 2006 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'
require 'yaml'
require 'time'
require 'cgi'
require 'ostruct'
require 'erb'
include ERB::Util

require 'version'
require 'config/format'


# utility logic

  # Wraps the given error inside the given message, while
  # preserving its original stack trace, and raises it.
  def raise_error aMessage, aError = $!
    raise aError.class, "#{aMessage}:\n#{aError}", aError.backtrace
  end

  # Returns a hyperlink to the given URL of
  # the given name and mouse-hover title.
  def link aUrl, aName = nil, aTitle = nil
    aName ||= aUrl
    %{<a href="#{aUrl}"#{%{ title="#{aTitle}"} if aTitle}>#{aName}</a>}
  end

  # Returns HTML for embedding an icon from the input/icons/ directory.
  def icon aFileName, aAlt = nil, aTitle = nil
    aTitle ||= aAlt

    %{<img class="icon" src="icons/#{aFileName}" alt="#{aAlt}" title="#{aTitle}" />}
  end

  # Returns a safe file name that is composed of the
  # given words and has the given file extension.
  def make_file_name aExtension, *aWords #:nodoc:
    aWords.join(' ').to_file_name.ext(aExtension)
  end

  class String
    # Transforms this string into a vaild file name that can be safely used
    # in a URL.  See http://en.wikipedia.org/wiki/URI_scheme#Generic_syntax
    def to_file_name
      downcase.strip.gsub(%r{[/;?#[:space:][:punct:]]+}, '-').gsub(/^-|-$/, '')
    end

    # Transforms this UTF-8 string into HTML entities.
    def to_html_entities
      unpack('U*').map! {|c| "&##{c};"}.join
    end

    # Transforms this string into a valid URI fragment.
    # See http://www.nmt.edu/tcc/help/pubs/xhtml/id-type.html
    def to_uri_fragment
      # remove HTML tags from the input
      buf = gsub(/<.*?>/, '')

      # The first or only character must be a letter.
      buf.insert(0, 'a') unless buf[0,1] =~ /[[:alpha:]]/

      # The remaining characters must be letters, digits, hyphens (-),
      # underscores (_), colons (:), or periods (.) or Unicode characters
      buf.unpack('U*').map! do |code|
        if code > 0xFF or code.chr =~ /[[:alnum:]\-_:\.]/
          code
        else
          32 # ASCII character code for a single space
        end
      end.pack('U*').strip.gsub(/[[:space:]-]+/, '-')
    end

    # Passes this string through ERB and returns the result.
    def thru_erb aBinding = Kernel.binding
      ERB.new(self).result(aBinding)
    end

    # Transforms this string into an escaped POSIX shell
    # argument whilst preserving Unicode characters.
    def shell_escape
      inspect.gsub(/\\(\d{3})/) { $1.to_i(8).chr }
    end


    @@uriFrags = []

    # Resets the list of uri_fragments encountered thus far.
    def String.reset_uri_fragments #:nodoc:
      @@uriFrags.clear
    end

    # Builds a table of contents from XHTML headings (<h1>, <h2>, etc.) found
    # in this string and returns an array containing [toc, text] where:
    #
    # toc::   the generated table of contents
    #
    # text::  a modified version of this string which
    #         contains anchors for the hyperlinks in
    #         the table of contents (so that the TOC
    #         can link to the content in this string)
    #
    def table_of_contents
      toc = '<ul>'
      prevDepth = 0
      prevIndex = ''

      text = gsub %r{<h(\d)(.*?)>(.*?)</h\1>$}m do
        depth, atts, title = $1.to_i, $2, $3.strip

        # generate a LaTeX-style index (section number) for the heading
          depthDiff = (depth - prevDepth).abs

          index =
            if depth > prevDepth
              toc << '<li><ul>' * depthDiff

              s = prevIndex + ('.1' * depthDiff)
              s.sub(/^\./, '')

            elsif depth < prevDepth
              toc << '</ul></li>' * depthDiff

              s = prevIndex.sub(/(\.\d+){#{depthDiff}}$/, '')
              s.next

            else
              prevIndex.next

            end

          prevDepth = depth
          prevIndex = index

        # generate a unique anchor for the heading
          frag = CGI.unescape(
            if atts =~ /id=('|")(.*?)\1/
              atts = $` + $'
              $2
            else
              title
            end
          ).to_uri_fragment

          frag << frag.object_id.to_s while @@uriFrags.include? frag
          @@uriFrags << frag

        # provide hyperlinks for traveling between TOC and heading
          dst = frag
          src = dst.object_id.to_s.to_uri_fragment

          dstUrl = '#' + dst
          srcUrl = '#' + src

          # forward link from TOC to heading
          toc << %{<li><a id="#{src}" href="#{dstUrl}">#{title}</a></li>}

          # reverse link from heading to TOC
          %{<h#{depth}#{atts}><a id="#{dst}" href="#{srcUrl}" class="toc-link">#{index}</a>&nbsp;&nbsp;#{title}</h#{depth}>}
      end

      if prevIndex.empty?
        toc = nil # there were no headings
      else
        toc << '</ul></li>' * prevDepth
        toc << '</ul>'

        # collapse redundant list elements
        while toc.gsub! %r{(<li>.*?)</li><li>(<ul>)}, '\1\2'
        end

        # collapse unnecessary levels
        while toc.gsub! %r{(<ul>)<li><ul>(.*)</ul></li>(</ul>)}, '\1\2\3'
        end
      end

      [toc, text]
    end
  end

  class Template < ERB
    # Returns the result of template evaluation thus far.
    attr_reader :buffer

    # aName:: String that replaces the ambiguous '(erb)' identifier in stack
    #         traces, so that the user can better determine the source of an
    #         error.
    #
    # args:: Arguments for ERB::new
    def initialize aName, *args
      # silence the code-only <% ... %> directive, just like PHP does
      args[0].gsub!(/^[ \t]*<%[^%=]((?!<%).)*?[^%]%>[ \t]*\r?\n/m) {|s| s.strip}

      args[3] = '@buffer'
      super(*args)

      @filename = aName
    end

    # Renders this template within a fresh object that
    # is populated with the given instance variables.
    def render_with aInstVars = {}
      context = Object.new.instance_eval do
        aInstVars.each_pair do |var, val|
          instance_variable_set var, val
        end

        binding
      end

      result(context)
    end
  end


  # Notify the user about some action being performed.
  def notify aAction, aMessage
    printf "%12s  %s\n", aAction, aMessage
  end

  # Writes the given content to the given file.
  def write_file aPath, aContent
    File.open(aPath, 'w') {|f| f << aContent}
  end

  COMMON_DEPS = FileList[__FILE__, 'output', 'config/**/*.{yaml,*rb}']

  # Registers a new Rake task for generating a HTML
  # file and returns the path of the output file.
  def generate_html_task aTask, aPage, aDeps, aRenderOpts = {} #:nodoc:
    dst = File.join('output', aPage.url)

    # register subdirs as task deps
    dst.split('/').inject do |base, ext|
      directory base
      aDeps << base

      File.join(base, ext)
    end

    file dst => aDeps + COMMON_DEPS do
      notify aPage.class, dst

      begin
        write_file dst, aPage.render(aRenderOpts)
      rescue Exception
        raise_error "An error occurred when generating the #{dst.inspect} file"
      end
    end

    task aTask => dst
    CLEAN.include dst

    dst
  end

  FEEDS = []
  Feed = Struct.new(:file, :entries, :name, :info, :summarize)

  # Registers a new Rake task for generating a feed.
  #
  # aFile:: path of the output file relative to the output/ directory
  # aItems:: array containing Chapter, Section, Listing, and Entry objects
  # aName:: title of the feed
  # aInfo:: description of the feed
  # aSummarize:: summarize blog entries in the feed?
  #
  def feed aFile, aItems, aName, aInfo = nil, aSummarize = BLOG.summarize_entries
    dst = File.join('output', aFile)
    entries = [aItems].flatten.uniq

    feedObj = Feed.new(aFile, entries, aName, aInfo, aSummarize)
    FEEDS << feedObj

    file dst => COMMON_DEPS + entries.map {|e| e.input_file} do |t|
      notify :feed, t.name
      write_file t.name, FEED_TEMPLATE.render_with(:@feed => feedObj)
    end

    task :feed => dst
    CLEAN.include dst
  end

# data structures

  # Interface to translations of English strings used in the core of Rassmalog.
  class Language < Hash
    def initialize aData = {}
      merge! aData
    end

    # Translates the given string and then formats (see String#format) the
    # translation with the given placeholder arguments.  If the translation
    # is not available, then the given string will be used instead.
    def [] aPhrase, *aArgs
      s = aPhrase.to_s
      if key? s
        super(s)
      else
        s
      end.to_s % aArgs
    end
  end

  # In order to mix-in this module, an object must:
  #
  # 1. have an associated template file (whose basename is
  #    specified by #template_name) in the config/ directory.
  #
  #    A default #template_name, which uses the
  #    name of the mixer's class, is provided.
  #
  # 2. define a #url method which returns a relative URL to it.
  #
  #   A default #url, which uses #name, is provided.
  #
  module TemplateMixin
    # Basename of the template file, which resides in the
    # config/ directory, used to render objects of this class.
    def template_name
      self.class.to_s
    end

    # Returns the template used to render objects of this class.
    def template
      Kernel.const_get(template_name.upcase << '_TEMPLATE')
    end

    # Returns the name of the instance variable for objects of this
    # class.  This variable is used in the template of this class.
    def template_ivar
      "@#{template_name.downcase}".to_sym
    end

    # Path (relative to the output/ directory)
    # to the HTML output file of this object.
    def url
      make_file_name('html', name)
    end

    # Transforms this object into HTML.
    def to_html aOpts = {}
      aOpts[:@summarize] = BLOG.summarize_entries unless aOpts.key? :@summarize
      aOpts[template_ivar] = self
      template.render_with(aOpts)
    end

    # Renders a complete HTML page for this object.
    def render aOpts = {}
      aOpts[:@target]  = self
      aOpts[:@title]   = self.name
      aOpts[:@content] = self.to_html(aOpts)

      html = HTML_TEMPLATE.render_with(aOpts)

      # make implicit relative paths into explicit ones
        pathPrefix = '../' * self.url.scan(%r{/+}).length

        html.gsub! %r{((?:href|src|action)\s*=\s*("|'))(.*?)(\2)} do
          head, body, tail = $1, $3.strip, $4

          if body !~ %r{^\w+:|^[/#?]}
            body.insert 0, pathPrefix
          end

          head << body << tail
        end

      html
    end

    # Returns a relative hyperlink to this object.
    #
    # aName:: sets the name of the hyperlink, if given
    # aAnchor:: adds a URI fragment to the hyperlink's URL, if given
    #
    def to_link aName = nil, aAnchor = nil
      addr = [url, aAnchor].compact.join('#')
      title = name.to_html
      link(addr, aName || title, aName && title)
    end
  end

  # In order to mix-in this module, an object must:
  #
  # 1. define a #parent method which returns
  #    the array that contains this object.
  #
  module SequenceMixin
    attr_writer :next, :prev

    # Returns the next section in the chapter.
    def next
      @next ||= sibling(+1)
    end

    # Returns the previous section in the chapter.
    def prev
      @prev ||= sibling(-1)
    end

    private

    def sibling aOffset
      src = parent.index(self)
      dst = src + aOffset
      parent[dst] unless dst < 0
    end
  end

  # A single blog entry.
  class Entry < Hash
    include SequenceMixin
      def parent
        ENTRIES
      end

    # {String object}
    # Title of this blog entry.
    attr_reader :name

    # {Time object}
    # Date when this blog entry was written.
    attr_reader :date

    # {String object}
    # Content of this blog entry.
    attr_reader :text

    # {Array of Section objects}
    # The categories in which this blog entry belongs.
    attr_reader :tags

    # {Section object}
    # Section object associated with the date of this blog entry.
    attr_reader :archive

    # {String object}
    # Path to the YAML input file of this blog entry.
    attr_reader :input_file

    # {String object}
    # Path to the HTML output file of this blog entry.
    attr_reader :output_file

    # {String object}
    # Path (relative to the input/ directory) to
    # the YAML input file of this blog entry.
    attr_reader :input_url

    # {String object}
    # Path (relative to the output/ directory) to
    # the HTML output file of this blog entry.
    attr_reader :output_url

    include TemplateMixin
      alias url output_url

    # aData:: the content of this Entry
    def initialize aData = {}
      merge! aData
    end

    # Returns true if this entry is hidden (the 'hide' parameter is enabled).
    def hide?
      @hidden
    end

    # Returns the summarized HTML content of this blog entry.  If there
    # is no summary or summarization is not possible, then returns nil.
    def summary
      if key? 'summary'
        self['summary'].to_s.thru_erb.to_html
      else
        case html.gsub(%r{<(h\d).*?>.*?</\1>}m, '') # omit headings from summary

        # the first HTML block-level element
        when %r{\A\s*<(\w+).*?>.*?</\1>}m
          $&

        # the first paragraph (a run of text delimited by newlines)
        when /\A.*?(?=\r?\n\s*\r?\n)/m
          $&

        end
      end
    end

    # Returns the absolute URL to this entry.
    def absolute_url
      File.join(BLOG.url, url)
    end

    # Sort chronologically.
    def <=> aOther
      aOther.date <=> @date
    end

    # Transforms the text of this entry into HTML and returns it.
    def html
      @html ||= Template.new("#{@input_file}:text", @text).render_with(template_ivar => self).to_html
    end

    # Returns a URL for submiting comments about this entry.
    def comment_url
      BLOG.email.to_url(name, File.join(BLOG.url, url))
    end
  end

  # A grouping of Entry objects based on some criteria, such as tag or archive.
  class Section < Array
    include TemplateMixin
      # Path (relative to the output/ directory)
      # to the HTML output file of this object.
      def url
        make_file_name('html', @chapter.name, name)
      end

    # The title of this section.
    attr_reader :name

    # The Chapter object to which this section belongs.
    attr_reader :chapter

    include SequenceMixin
      alias parent chapter

    def initialize aName, aChapter
      @name = aName
      @chapter = aChapter
    end

    # Sort alphabetically.
    def <=> aOther
      if parent == ARCHIVES
        first.date <=> aOther.first.date
      else
        @name <=> aOther.name
      end
    end
  end

  # A list of Section objects.
  class Chapter < Array
    include TemplateMixin

    # The title of this chapter.
    attr_reader :name

    def initialize aName
      @name = aName
      @cache = Hash.new do |h,k|
        h[k] = find {|s| s.name == k} or raise \
        "could not find section #{k.inspect} in chapter #{aName.inspect}"
      end
    end

    # Allows you to access a section using its name
    # or through the usual Ruby array access idioms.
    def [] aName, *args
      if aName.is_a? Integer or aName.is_a? Range
        super(aName, *args)
      else
        @cache[aName.to_s]
      end
    end
  end

  # A list of Entry objects.  This class is used to fulfill the
  # purpose of generating a HTML page with some Entry objects on it,
  # but without resorting to the full capability of the Section class.
  class Listing < Array #:nodoc:
    include TemplateMixin

    # The title of this object.
    attr_reader :name

    def initialize aName
      @name = aName
    end
  end


# configuration stage

  # load blog configuration
    begin
      data = YAML.load_file('config/blog.yaml')
    rescue Exception
      raise_error 'An error occurred when loading the blog configuration file (config/blog.yaml)'
    end

    BLOG = OpenStruct.new(data)

    # allow blog parameters whose values are
    # eRuby templates to be evaluated lazily
    class << BLOG
      %w[name info author email url encoding language locale front_page].each do |m|
        class_eval %{
          alias old_#{m} #{m}

          def #{m}
            @#{m} ||=
              if v = old_#{m}
                begin
                  v.to_s.thru_erb
                rescue Exception
                  raise_error 'Unable to parse the #{m.inspect} parameter (which is defined in config/blog.yaml)'
                end
              end
          end
        }
      end
    end

    # localize Time formats into user's language
    if locale = BLOG.locale
      begin
        require 'locale'
        Locale.setlocale(Locale::LC_ALL, locale)

      rescue SystemCallError
        raise "Your system does not support the #{locale.inspect} locale (which is defined by the 'locale' parameter in config/blog.yaml)."

      rescue LoadError
        raise "Cannot activate the #{locale.inspect} locale (which is defined by the 'locale' parameter in config/blog.yaml) because your system does not have the ruby-locale library."
      end
    end

    class << BLOG.links
      # Converts this hierarchical menu of links into HTML.
      def to_html
        @html ||= render_menu(self)
      end

      private

      # Expands the given hierarchical menu into an itemized list of hyperlinks.
      # * Each link name is first evaluated by ERB and then converted into HTML.
      # * Each link URL is only evaluated by ERB; there is no HTML conversion.
      def render_menu aNode
        result = ''

        if aNode.respond_to? :to_ary
          aNode.each do |node|
            result << render_menu(node)
          end

        elsif aNode.respond_to? :each_pair
          aNode.each_pair do |name, node|
            result << "<li>#{
              name = name.to_s.thru_erb.to_html

              if node.respond_to? :to_ary
                "#{name} <ul>#{render_menu node}</ul>"
              else
                url = node.to_s.thru_erb
                %{<a href="#{url}">#{name}</a>}
              end
            }</li>"
          end

        else
          result << "<li>#{aNode}</li>"
        end

        result
      end
    end

    class << BLOG.email
      # Converts this e-mail address into an obfuscated 'mailto:' URL.
      def to_url aSubject = nil, aBody = nil
        addr = "mailto:#{to_s.to_html_entities}"
        subj = "subject=#{u aSubject}" if aSubject
        body = "body=#{u aBody}" if aBody

        rest = [subj, body].compact
        addr << '?' << rest.join('&amp;') unless rest.empty?
        addr
      end
    end

  # load translations
    data = YAML.load_file("config/lang/#{BLOG.language}.yaml") rescue {}
    LANG = Language.new(data)

  # load templates
    FileList['config/*.erb'].each do |src|
      var = "#{File.basename(src, File.extname(src)).upcase}_TEMPLATE"
      val = Template.new(src, File.read(src))
      Kernel.const_set var.to_sym, val
    end

    class << HTML_TEMPLATE
      alias old_result result

      def result *args
        # give this page a fresh set of anchors, so that each entry's
        # table of contents does not link to other entry's contents
        String.reset_uri_fragments

        old_result(*args)
      end
    end

# input processing stage

  TAGS        = Chapter.new LANG['Tags']
  ARCHIVES    = Chapter.new LANG['Archives']
  ENTRIES     = Listing.new LANG['All entries']
  NEW_ENTRIES = Listing.new LANG['New entries']


  tagStore = {}
  archiveStore = {}

  # hooks up the given entry with the given section (by
  # name) and chapter.  then returns the section object.
  def hookup aEntry, aStore, aName, aChapter #:nodoc:
    unless aStore.key? aName
      s = Section.new(aName, aChapter)
      aChapter << s
      aStore[aName] = s
    end

    aStore[aName] << aEntry
  end


  # generate HTML for entry files
    ENTRY_FILES = []
    ENTRY_FILES_EXCLUDED = [] # excluded from processing, so just copy them over
    entryByInputUrl = {}

    FileList['{input,entries}/**/*.yaml'].each do |src|
      begin
        data = YAML.load_file(src)

        if data.is_a? Hash and
           data.key? 'name' and
           data.key? 'text'
        then
          src =~ %r{^.*?/}
          srcDir, srcUrl = $&, $'


          entry = Entry.new(data)
          entryByInputUrl[srcUrl] = entry

          # populate the entry's methods (see Entry class definition)
          entryProp = {
            :name => data['name'].to_s.thru_erb,

            :date => entryDate = (
              if data.key? 'date'
                begin
                  Time.parse(data['date'].to_s.thru_erb)
                rescue ArgumentError
                  raise_error "Unable to parse the 'date' parameter"
                end
              else
                File.mtime(src)
              end
            ),

            :text => data['text'].to_s,

            :input_url => srcUrl,
            :input_file => src,

            :output_url => dstUrl = (
              # for entries that override the output file name
              if data.key? 'output_file'
                data['output_file'].to_s.thru_erb

              # for entries in entries/, calculate output file name
              elsif srcDir == 'entries/'
                make_file_name('html', entryDate.strftime('%F'), data['name'])

              # for entries in input/, use the original file name
              else
                srcUrl.ext('html')
              end
            ),

            :output_file => File.join('output', dstUrl),
          }

          if entryProp[:hidden] = data['hide']
            entryProp[:tags] = []
            entryProp[:archive] = nil
          else
            entryProp[:tags] =
              [data['tags']].flatten.compact.uniq.sort.map do |name|
                hookup(entry, tagStore, name, TAGS)
              end

            name = entryProp[:date].strftime(BLOG.archive_frequency)
            entryProp[:archive] = hookup(entry, archiveStore, name, ARCHIVES)

            ENTRIES << entry
          end

          entryProp.each_pair do |prop, value|
            entry.instance_variable_set("@#{prop}", value)
          end

          ENTRY_FILES << src
          generate_html_task :entry, entry, [src], :@summarize => false, :@solo => true
        else
          notify :skip, src
          ENTRY_FILES_EXCLUDED << src
        end

      rescue Exception
        raise_error "An error occurred when loading the #{src.inspect} file"
      end
    end

    ENTRIES.sort! # chronological sort

  # establish dependencies between chronologically adjacent entries so that
  # the next/prev | older/newer links (emitted by the blog entry template)
  # are coherent in the case of random entry insertion and deletion
    require 'enumerator'

    ENTRIES.each_cons(3) do |(a, b, c)|
      a.next = b
      b.prev = a

      b.next = c
      c.prev = b

      file b.output_file => [a.input_file, c.input_file]
    end

  # generate the search page
    if SEARCH_PAGE = entryByInputUrl['search.yaml']
      dst = SEARCH_PAGE.output_file
      file dst => ENTRY_FILES # the search page depends on ALL entries

      # give the search page its own Rake task, otherwise it is
      # created every time the :entry task is invoked -- this defeats
      # the ability to rapidly preview entries while editing them.
      Rake::Task[:entry].prerequisites.delete dst
      task :search => dst
    end

  # generate list of all entries
    generate_html_task :entry_list, ENTRIES, ENTRY_FILES

  # generate list of recent entries
    recent = BLOG.new_entries ? ENTRIES[0, BLOG.new_entries] : ENTRIES
    recentFiles = recent.map {|e| e.input_file}

    NEW_ENTRIES.concat recent
    generate_html_task :entry_list, NEW_ENTRIES, recentFiles

  # generate HTML for tags and archives
    [TAGS, ARCHIVES].each do |chapter|
      chapter.sort!

      chapterDeps = []
      chapter.each do |section|
        section.sort!

        sectionDeps = section.map {|e| e.input_file}
        generate_html_task :entry_meta, section, sectionDeps

        chapterDeps.concat sectionDeps
      end

      generate_html_task :entry_meta, chapter, chapterDeps
    end


# output generation stage

  task :default => :gen

  desc "Generate the blog."
  task :gen

  desc "Copy files from input/ into output/"
  task :copy

  desc "Generate the blog search page."
  task :search

  desc "Generate HTML for blog entries."
  task :entry

  desc "Generate HTML for tags and archives."
  task :entry_meta

  desc "Generate HTML for recent/all entry lists."
  task :entry_list

  desc "Generate RSS feeds for the blog."
  task :feed

  desc "Regenerate the blog from scratch."
  task :regen => [:clobber, :gen]

  directory 'output'
  CLOBBER.include 'output'

  # copy everything from input/ into output/
    srcList = Dir.glob('input/**/*', File::FNM_DOTMATCH).reject do
                |s| File.directory? s and Dir.entries(s) != %w[. ..]
              end - ENTRY_FILES + ENTRY_FILES_EXCLUDED

    dstList = srcList.map {|s| s.sub 'input', 'output'}

    task :copy => 'output' do
      srcList.zip(dstList).each do |(src, dst)|
        alreadyCopied =
          begin
            File.lstat(dst).mtime >= File.lstat(src).mtime
          rescue Errno::ENOENT
            false
          end

        unless alreadyCopied
          notify :copy, dst

          dir = File.dirname(dst)
          mkdir_p dir unless File.directory? dir

          remove_entry_secure dst, true
          copy_entry src, dst, !File.symlink?(src)
        end
      end
    end

  # generate the front page
    dst     = 'output/index.html'
    src     = BLOG.front_page || NEW_ENTRIES.url
    srcUrl  = src.split('/').map {|s| u(s)}.join('/')
    srcLink = link(srcUrl, src)
    srcPath = File.join('output', src)

    file dst => COMMON_DEPS + [srcPath] do |t|
      notify :front_page, srcPath

      if srcUrl =~ %r{/}
        write_file t.name, %{<html><head><meta http-equiv="refresh" content="0; url=#{srcUrl}"/></head><body><p>#{LANG['You are now being redirected to %s.', srcLink]}</p></body></html>}
      else
        cp srcPath, t.name, :preserve => true
      end
    end

    task :entry_list => dst
    CLEAN.include dst


# output publishing stage

  desc "Preview your blog while writing."
  task :preview do
    loop do
      system $0
      sleep 1
    end
  end

  desc "Upload the blog to your website."
  task :upload => [:gen, 'output'] do
    whole = 'output'
    parts = Dir.glob('output/*', File::FNM_DOTMATCH)[2..-1].
            map {|f| f.shell_escape}.join(' ')

    sh BLOG.uploader.to_s.thru_erb(binding)
  end

