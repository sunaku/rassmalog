# This file contains the core of Rassmalog.
#--
# Copyright 2006-2007 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'
require 'config/format'
require 'yaml'
require 'ostruct'
require 'date'

require 'erb'
include ERB::Util


# project information

  GENERATOR = OpenStruct.new(
    :name     => 'Rassmalog',
    :version  => '5.1.0',
    :date     => '2007-07-04',
    :url      => 'http://rassmalog.rubyforge.org'
  )

  class << GENERATOR
    def to_s
      name + ' ' + version
    end

    def to_link
      %{<a href="#{url}">#{self}</a>}
    end
  end


# utility logic

  class DateTime
    # Returns the RFC-822 representation, which
    # is required by RSS, of this object.
    def rfc822
      strftime "%a, %d %b %Y %H:%M:%S %z"
    end
  end

  class String
    # Transforms this string into a vaild file name that can be safely used
    # in a URL.  See http://en.wikipedia.org/wiki/URI_scheme#Generic_syntax
    def to_file_name
      gsub(%r{[/;?#]+}, '-'). # these are *reserved* characters in URL syntax
      downcase.               # it's hard to remember capitalization in URLs
      gsub(/\s+/, '-').       # remove the need for %20 escapes in URLs
      squeeze('-')
    end

    # Transforms this UTF-8 string into HTML entities.
    def to_html_entities
      unpack('U*').map! {|c| "&##{c};"}.join
    end

    # Transforms this string into a valid XHTML anchor (ID attribute).
    # See http://www.nmt.edu/tcc/help/pubs/xhtml/id-type.html
    def to_html_anchor
      # remove HTML tags from the input
      buf = self.gsub(/<.*?>/, '')

      # The first or only character must be a letter.
      buf.insert(0, 'a') unless buf[0,1] =~ /[[:alpha:]]/

      # The remaining characters must be letters,
      # digits, hyphens (-), underscores (_), colons
      # (:), or periods (.) [or Unicode characters]
      buf.unpack('U*').map! do |code|
        if code > 0xFF or code.chr =~ /[[:alnum:]\-_:\.]/
          code
        else
          ?_
        end
      end.pack('U*')
    end

    # Transforms this string into an escaped POSIX shell
    # argument whilst preserving Unicode characters.
    def shell_escape
      inspect.gsub(/\\(\d{3})/) {$1.to_i(8).chr}
    end


    @@anchors = []

    # Resets the list of anchors encountered thus far.
    def String.reset_anchors
      @@anchors.clear
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
    # If a block is given, it will be invoked every time a
    # heading is found, with information about the found heading.
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

        # generate a unique HTML anchor for the heading
          anchor = CGI.unescape(
            if atts =~ /id=('|")(.*?)\1/
              atts = $` + $'
              $2
            else
              title
            end
          ).to_html_anchor

          anchor << anchor.object_id.to_s while @@anchors.include? anchor
          @@anchors << anchor

        yield title, anchor, index, depth, atts if block_given?

        # provide hyperlinks for traveling between TOC and heading
          dst = anchor
          src = dst.object_id.to_s.to_html_anchor

          # forward link from TOC to heading
          toc << %{<li><a id="#{src}" href="##{dst}">#{title}</a></li>}

          # reverse link from heading to TOC
          %{<h#{depth}#{atts}><a id="#{dst}" href="##{src}">#{index}</a> &nbsp; #{title}</h#{depth}>}
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

  class ERB
    alias old_initialize initialize

    # A version of ERB whose embedding tags behave like those
    # of PHP.  That is, only <%= ...  %> tags produce output,
    # whereas <% ...  %> tags do *not* produce any output.
    def initialize aInput, *aArgs
      # ensure that only <%= ... %> tags generate output
        input = aInput.gsub %r{<%=.*?%>}m do |s|
          if ($' =~ /\r?\n/) == 0
            s << $&
          else
            s
          end
        end

        aArgs[1] = '>'

      old_initialize input, *aArgs
    end

    # Renders this template within a fresh object initialized with the given
    # instance variables and configured by the given block (if given).
    def render_with aInstVars = {}, &aConfigBlock
      dummy = Object.new

      aInstVars.each_pair do |var, val|
        dummy.instance_variable_set var, val
      end

      dummy.instance_eval(&aConfigBlock) if block_given?

      context = dummy.instance_eval {binding}
      result(context) # eval the ERB template
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

  # Registers a new Rake task for generating a HTML
  # file and returns the path of the output file.
  def generate_html_task aTask, aPage, *aDeps #:nodoc:
    dst = File.join('output', aPage.url)

    # register subdirs as task deps
    dst.split('/').inject do |base, ext|
      directory base
      aDeps << base

      File.join(base, ext)
    end

    file dst => aDeps.flatten + COMMON_DEPS do
      notify aPage.class, dst
      write_file dst, aPage.render
    end

    task aTask => dst
    CLOBBER.include dst

    dst
  end

  # Interface to translations of English strings used in the core of Rassmalog.
  class Language < OpenStruct
    # Translates the given string and then formats (see String#format) the
    # translation with the given placeholder arguments.  If the translation
    # is not available, then the given string will be used instead.
    def [] aString, *aArgs
      (self.send(aString) || aString).to_s % aArgs
    end
  end


# data structures for organizing entries

  # Something that can be (hyper)linked to.
  # Objects that mix-in this module must define
  # a #name or #to_s method, whose value is used
  # when determining the URL for this object.
  module Linkable
    def to_s
      if respond_to? :name
        name
      else
        super
      end
    end

    # Returns a relative URL to this object.
    def url
      if is_a? Chapter or is_a? DataIndex
        File.join LANG[self.name].to_file_name, 'index.html'
      else
        prefix =
          if is_a? Section
            chapter.name
          elsif is_a? Entry
            "Entries"
          elsif is_a? Page
            "Pages"
          else
            self.class.to_s
          end

        File.join LANG[prefix].to_file_name, to_s.to_file_name << '.html'
      end
    end

    # Returns a relative hyperlink to this object.
    def to_link aName = self.name
      %{<a href="#{h url}">#{aName.to_html}</a>}
    end

    # Compares this object to the given one.
    def <=> other
      url <=> other.url
    end
  end

  # The class which includes this module must have an
  # associated ERB template in the config/ directory.
  module Renderable
    # Basename of the ERB template in the config/ directory.
    def template_name
      self.class.to_s
    end

    # Returns the ERB template inside this wrapper.
    def template
      Kernel.const_get(template_name.to_s.upcase << '_TEMPLATE')
    end

    def template_ivar
      :"@#{self.class.to_s.downcase}"
    end

    # Transforms this object into HTML.
    def to_html aOpts = {}
      aOpts[template_ivar] = self
      template.render_with aOpts
    end

    # Renders a HTML page for this object.
    def render aOpts = {}
      aOpts[:@content] = self.to_html#(aOpts)
      aOpts[:@target] = self
      aOpts[:@title]  = self.name


      html = HTML_TEMPLATE.render_with(aOpts)

      # make implicit relative paths into explicit ones
        pathPrefix = "../" * self.url.scan(%r{/+}).length

        html.gsub! %r{((?:href|src)\s*=\s*("|'))(.*?)(\2)} do
          head, body, tail = $1, $3.strip, $4

          if body !~ %r{^\w+:|^[/#?]|^\.+/}
            body.insert 0, pathPrefix
          end

          head << body << tail
        end

      html
    end
  end


  class UserData < OpenStruct
    include Renderable
    include Linkable
  end

  # A static web page.
  class Page < UserData
    # Returns the text of this object with ERB directives evaluated.
    def text
      unless defined? @expandedText
        # evaluate ERB directives within the entry
        @expandedText = ERB.new(super).render_with(template_ivar => self)
      end

      @expandedText
    end

    # Returns a URL for submiting comments about this entry.
    def comment_url
      BLOG.email.to_url name, File.join(BLOG.url, url)
    end
  end

  # A single blog entry.
  class Entry < Page
    include Renderable
    include Linkable
      def to_s
        stamp = date.strftime "%F"
        "#{stamp}-#{name}"
      end

    # Compares this entry to the given entry.  This
    # is used to sort a list of entries by date.
    def <=> aOther
      date <=> aOther.date
    end
  end


  class MetaData
    include Renderable
    include Linkable

    attr_reader :name
  end

  # A listing of blog entries (Entry objects).
  class Section < MetaData
    attr_reader :entries, :chapter

    # aName:: name of this section
    # aEntries:: Entry objects that belong in this section
    # aChapter:: Chapter object which contains this section
    def initialize aName, aEntries, aChapter
      @name = aName
      @entries = aEntries
      @chapter = aChapter
    end

    # Returns the next section in the chapter.
    def next
      sibling(+1)
    end

    # Returns the previous section in the chapter.
    def prev
      sibling(-1)
    end

    private

    def sibling aOffset
      list = chapter.sections
      pos = list.index(self)

      list[(pos + aOffset) % list.length]
    end
  end

  # A listing of sections (Section objects).
  class Chapter < MetaData
    attr_reader :sections

    # aName:: name of this Chapter
    # aHash:: mapping from Section name to array of Entry
    def initialize aName, aHash
      @name = LANG[aName]
      @fileName = aName
      @sections = []

      aHash.each_pair do |k, v|
        @sections << Section.new(k, v, self)
      end

      @sections.sort!
    end
  end


  class DataIndex
    include Linkable

    include Renderable
      def template_name
        :index
      end

      def to_html aOpts = {}
        aOpts[:@title] = self.name
        super aOpts
      end

    def initialize aSources
      @sources = aSources
    end

    def to_html aOpts = {}
      unless aOpts.key? :@summarize
        aOpts[:@summarize] = BLOG.summarize_entries
      end

      content = @sources.map do |k|
        k.to_html aOpts
      end.join

      super :@content => content
    end
  end

  class PageIndex < DataIndex
    def name
      LANG[:Pages]
    end
  end

  class EntryIndex < DataIndex
    def name
      LANG[:Entries]
    end
  end

  class SearchIndex < EntryIndex
    def template_name
      :search
    end

    def name
      LANG[:Search]
    end

    def to_html
      super :@summarize => false
    end
  end


# input processing stage

  # load blog configuration
    BLOG = load_yaml_file('config/blog.yaml')

    class << BLOG.menu
      # Converts this hierarchical menu into HTML.
      def to_html
        @html ||= render_menu self
      end

      private

      # Expands the given hierarchical menu into an itemized list of hyperlinks.
      def render_menu aMenu
        result = ''

        if aMenu.respond_to? :to_ary
          aMenu.each do |link|
            result << render_menu(link)
          end
        elsif aMenu.respond_to? :each_pair
          aMenu.each_pair do |name, url|
            link = if url.respond_to? :to_ary
              "#{name} <ul>#{render_menu url}</ul>"
            else
              %{<a href="#{url}">#{name.to_html}</a>}
            end

            result << "<li>#{link}</li>"
          end
        else
          result << "<li>#{aMenu}</li>"
        end

        result
      end
    end

    class << BLOG.email
      def to_url aSubject = nil, aBody = nil
        addr = "mailto:#{self.to_html_entities}"
        subj = "subject=#{u aSubject}" if aSubject
        body = "body=#{u aBody}" if aBody

        rest = [subj, body].compact
        unless rest.empty?
          addr << '?' << rest.join('&amp;')
        end

        addr
      end
    end

  # load translations
    langFile = "config/lang/#{BLOG.language}.yaml"
    LANG = load_yaml_file(langFile, Language) rescue Language.new

  # load templates
    FileList['config/*.erb'].each do |f|
      name = File.basename(f, File.extname(f))
      var = "#{name.upcase}_TEMPLATE"

      Kernel.const_set var.to_sym, ERB.new(File.read(f))
    end

    class << HTML_TEMPLATE
      alias old_result result

      def result *args
        # give this page a fresh set of anchors, so that each entry's
        # table of contents does not link to other entry's contents
        String.reset_anchors

        old_result(*args)
      end
    end

  # load static web pages
    PAGE_FILES = FileList['pages/**/*.yaml']

    PAGES = PAGE_FILES.map do |src|
      page = load_yaml_file(src, Page)
      page.src_file = src
      page
    end

  # load blog entries
    ENTRY_FILES = FileList['entries/**/*.yaml']

    ENTRIES = ENTRY_FILES.map do |src|
      entry          = load_yaml_file(src, Entry)
      entry.src_file = src
      entry.date     = DateTime.parse(entry.date.to_s)

      tags           = entry.tags.to_a rescue [entry.tags]
      entry.tags     = tags.flatten.compact.uniq

      entry
    end.sort.reverse!

    # Returns the most recent entries
    def ENTRIES.recent
      self[0, BLOG.recent_entries || 0]
    end

  # organize blog entries into chapters
    tags   = Hash.new {|h,k| h[k] = []}
    months = Hash.new {|h,k| h[k] = []}

    # parse tags and months from entries
      ENTRIES.each do |entry|
        entry.tags.each do |tag|
          tags[tag] << entry
        end.clear # will be restored later

        months[entry.date.strftime(BLOG.archive_frequency)] << entry
      end

    # organize entries into sections
      TAGS = Chapter.new('Tags', tags)
      ARCHIVES = Chapter.new('Archives', months)

      # restore tags for entry
        TAGS.sections.each do |tag|
          tag.entries.each do |entry|
            entry.tags << tag
          end
        end

        ARCHIVES.sections.each do |month|
          month.entries.each do |entry|
            entry.archive = month
          end
        end

    CHAPTERS = [TAGS, ARCHIVES]

    ENTRY_INDEX = EntryIndex.new(ENTRIES)
    PAGE_INDEX = PageIndex.new(PAGES)
    SEARCH_INDEX = SearchIndex.new(ENTRIES + PAGES)


# output generation stage

  desc "Generate the blog."
  task :default => [:copy, :page, :entry, :section, :chapter, :index, :feed]

  desc "Copy files from input/ into output/"
  task :copy

  desc "Generate HTML for static web pages."
  task :page

  desc "Generate HTML for entries."
  task :entry

  desc "Generate HTML for sections."
  task :section

  desc "Generate HTML for chapters."
  task :chapter

  desc "Generate HTML for indices."
  task :index

  desc "Generate RSS feed for the blog."
  task :feed

  desc "Regenerate the blog from scratch."
  task :regen => [:clobber, :default]

  CONFIG_FILES = FileList['config/**/*.{yaml,*rb}']
  COMMON_DEPS  = ['output'] + CONFIG_FILES

  # create output directory
    directory 'output'
    CLOBBER.include 'output'

  # copy everything from input/ into output/
    srcList = Dir.glob('input/**/*', File::FNM_DOTMATCH).
              reject {|s| File.basename(s) =~ /^\.{1,2}$/}

    dstList = srcList.map {|s| s.sub 'input', 'output'}
    CLEAN.include dstList

    task :copy do
      Rake::Task['output'].invoke

      srcList.zip(dstList).each do |(src, dst)|
        alreadyCopied =
          begin
            File.lstat(dst).mtime >= File.lstat(src).mtime
          rescue Errno::ENOENT
            false
          end

        unless alreadyCopied
          notify :copy, dst
          remove_entry_secure dst, true
          copy_entry src, dst, !File.symlink?(src)
        end
      end
    end

  # generate HTML for static web pages
    PAGES.each do |page|
      page.dst_file = generate_html_task(:page, page, page.src_file)
    end

  # generate HTML for blog entries
    ENTRIES.each do |entry|
      entry.dst_file = generate_html_task(:entry, entry, entry.src_file)
    end

  # generate HTML for sections and chapters
    CHAPTERS.each do |chapter|
      chapterDeps = []

      chapter.sections.each do |section|
        sectionDeps = section.entries.map {|e| e.src_file}
        generate_html_task :section, section, sectionDeps

        chapterDeps.concat sectionDeps
      end

      generate_html_task :chapter, chapter, chapterDeps
    end

  # generate entry list and search section
    generate_html_task :index, ENTRY_INDEX, ENTRY_FILES
    generate_html_task :index, PAGE_INDEX, PAGE_FILES
    generate_html_task :index, SEARCH_INDEX, ENTRY_FILES, PAGE_FILES

  # generate front section
    dst = 'output/index.html'

    if BLOG.front_page
      src = BLOG.front_page

      file dst => COMMON_DEPS do
        notify 'front page', File.join('output', src)
        write_file dst, %{<META HTTP-EQUIV="Refresh" CONTENT="0; URL=#{h src}">}
      end
    else
      file dst => COMMON_DEPS + ENTRIES.recent.map {|e| e.src_file} do
        list = EntryIndex.new(ENTRIES.recent)
        class << list
          def url
            'index.html'
          end
        end

        write_file dst, list.render
      end
    end

    task :index => dst
    CLOBBER.include dst

  # generate RSS feed
    file 'output/rss.xml' => ENTRY_FILES + COMMON_DEPS do |t|
      notify 'RSS feed', t.name
      write_file t.name, RSS_TEMPLATE.result(binding)
    end

    task :feed => 'output/rss.xml'
    CLOBBER.include 'output/rss.xml'


# output publishing stage

  desc "Upload the blog to your website."
  task :upload => [:default, 'output'] do
    whole = 'output'
    parts = Dir.glob('output/*', File::FNM_DOTMATCH)[2..-1].
            map {|f| f.shell_escape}.join(' ')

    sh ERB.new(BLOG.uploader.to_s).result(binding)
  end


# utility tasks

  directory 'entries/import'

  desc "Import blog entries from RSS feed on STDIN."
  task :import => 'entries/import' do
    require 'cgi'
    require 'rexml/document'

    REXML::Document.new(STDIN.read).each_element '//item' do |src|
      name = CGI.unescapeHTML src.elements['title'].text
      date = src.elements['pubDate'].text rescue Time.now
      tags = src.get_elements('category').map {|e| e.text} rescue []
      text = CGI.unescapeHTML src.elements['description'].text
      from = CGI.unescape src.elements['link'].text

      dst = "entries/import/#{name.to_file_name}.yaml"

      entry = %w[from name date tags].
        map {|var| {var => eval(var)}.to_yaml.sub(/^---\s*$/, '')}.
        join << "\ntext: |\n#{text.gsub(/^/, '  ')}"

      notify :import, dst
      write_file dst, entry
    end
  end
