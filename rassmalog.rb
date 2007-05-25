# The core of Rassmalog.
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
    :version  => '4.1.0',
    :date     => '2007-05-05',
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
    # Returns the RFC-822 representation, which is required by RSS, of this
    # object.
    def rfc822
      strftime "%a, %d %b %Y %H:%M:%S %Z"
    end
  end

  class String
    # Transforms this string into a vaild file name that can be safely used in a
    # URL. See http://en.wikipedia.org/wiki/URI_scheme#Generic_syntax
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
      # The first or only character must be a letter.
        buf =
          if self[0,1] =~ /[[:alpha:]]/
            self
          else
            'a' + self
          end

      # The remaining characters must be letters, digits, hyphens (-),
      # underscores (_), colons (:), or periods (.) [or Unicode characters]
        buf.unpack('U*').map! do |code|
          if code > 0xFF or code.chr =~ /[[:alnum:]\-_:\.]/
            code
          else
            ?_
          end
        end.pack('U*')
    end

    # Transforms this string into an escaped POSIX shell argument.
    def to_shell_arg
      gsub %r{[[:space:][:punct:]]} do |match|
        "\\" << match
      end
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
    # text::  a modified version of this string which contains anchors for the
    #         hyperlinks in the table of contents (so that the TOC can link to
    #         the content in this string)
    #
    # If a block is given, it will be invoked every time a heading is found,
    # with information about the found heading.
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

    # A version of ERB whose embedding tags behave like those of PHP. That is,
    # only <%= ... %> tags produce output, whereas <% ... %> tags do *not*
    # produce any output.
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

    # Renders this template within a fresh object configured by the given block.
    def render_with &aBlock
      dummy = Object.new
      dummy.instance_eval(&aBlock)
      result dummy.instance_eval {binding}
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

  # Registers a new Rake task for generating a HTML file and returns the path of
  # the output file.
  def generate_html_task aTask, aPage, *aDeps #:nodoc:
    dst = File.join('output', aPage.url)

    file dst => aDeps.flatten + COMMON_DEPS do
      notify aPage.class, dst
      write_file dst, aPage.render
    end

    task aTask => dst
    CLOBBER.include dst

    dst
  end

  # Generates an index, which is not a fully qualified Page but behaves like
  # one, of entries.
  #
  # NOTE: the aName parameter will be translated later by this method, so only
  # provide English strings here.
  def generate_special_index aName, aEntries, aMode, aFileName = nil #:nodoc:
    dst = aFileName || File.join('output', "index_#{aName.downcase}.html".to_file_name)

    file dst => aEntries.map {|e| e.src_file} + COMMON_DEPS do
      title = LANG[aName]

      index = INDEX_TEMPLATE.render_with do
        @name = aName
        @title = title
        @content = aEntries.map {|e| e.to_html aMode}.join
      end

      html = HTML_TEMPLATE.render_with do
        @title = title
        @content = index
      end

      notify aName, dst
      write_file dst, html
    end

    task :index => dst
    CLOBBER.include dst
  end


# data structures for organizing entries

  # Something that can be (hyper)linked to. Objects that mix-in this module must
  # define a #to_s method, whose value is used when determining the URL for this
  # object.
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

  # Interface to translations.
  class Language < OpenStruct
    # Translates the given string and then formats (see String#format) the
    # translation with the given placeholder arguments. If the translation is
    # not available, then the given string will be used instead.
    def [] aString, *aArgs
      (self.send(aString) || aString) % aArgs
    end
  end

  # A single blog entry.
  class Entry < OpenStruct
    include Linkable

    def initialize aHash = nil
      @rawText = aHash['text']
      super
    end

    def text
      # evaluate ERB directives within the entry
      @text ||= ERB.new(@rawText).result
    end

    def url
      stamp = date.strftime "%F"
      "#{stamp}-#{name}.html".to_file_name
    end

    # Returns a URL for submiting comments about this entry.
    def comment_url
      BLOG.email.to_url name, BLOG.url + '/' + url
    end

    # Transforms this entry into HTML. If summarize is enabled, then only the
    # first paragraph of this entry's content will be included in the result.
    def to_html aSummarize = false
      entry = self

      ENTRY_TEMPLATE.render_with do
        @entry = entry
        @summarize = aSummarize
      end
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
        addr = "mailto:#{self}"
        subj = "subject=#{u aSubject}" if aSubject
        body = "body=#{u aBody}" if aBody

        rest = [subj, body].compact
        unless rest.empty?
          addr << '?' << rest.join('&')
        end

        addr.to_html_entities
      end
    end

  # load templates
    FileList['config/*.erb'].each do |f|
      name = File.basename(f, File.extname(f))
      var = "#{name.upcase}_TEMPLATE"

      Kernel.const_set var.to_sym, ERB.new(File.read(f))
    end

    class << HTML_TEMPLATE
      alias old_result result

      def result *a
        # give this page a fresh set of anchors, so that each entry's table of
        # contents does not link to other entry's contents
        String.reset_anchors

        old_result(*a)
      end
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
      entry.tags.flatten!
      entry.tags.compact!
      entry.tags.uniq!

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


# output generation stage

  desc "Generate the blog."
  task :default => [:copy, :entry, :page, :chapter, :index, :feed]

  desc "Copy files from input/ into output/"
  task :copy

  desc "Generate HTML for entries."
  task :entry

  desc "Generate HTML for pages."
  task :page

  desc "Generate HTML for chapters."
  task :chapter

  desc "Generate HTML for indices."
  task :index

  desc "Generate RSS feed for the blog."
  task :feed

  desc "Regenerate the blog from scratch."
  task :regen => [:clobber, :default]

  CONFIG_FILES = FileList['config/**/*']
  COMMON_DEPS = ['output'] + CONFIG_FILES

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
          remove_entry_secure dst, true
          notify :copy, dst
          copy_entry src, dst, !File.symlink?(src)
        end
      end
    end

  # generate HTML for blog entries
    ENTRIES.each do |entry|
      entry.dst_file = generate_html_task(:entry, entry, entry.src_file)
    end

  # generate HTML for pages and chapters
    CHAPTERS.each do |chapter|
      chapterDeps = []

      chapter.pages.each do |page|
        pageDeps = page.entries.map {|e| e.src_file}
        generate_html_task :page, page, pageDeps

        chapterDeps.concat pageDeps
      end

      generate_html_task :chapter, chapter, chapterDeps
    end

  # generate entry list and search page
    generate_special_index "Entries", ENTRIES, true
    generate_special_index "Search", ENTRIES, false

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
            map {|f| f.to_shell_arg}.join(' ')

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
