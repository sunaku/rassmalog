# project information

Rassmalog = {
  :name     => 'Rassmalog',
  :version  => '12.0.2',
  :release  => '2008-10-16',
  :website  => 'http://rassmalog.rubyforge.org'
}

class << Rassmalog
  # Returns the name and version of Rassmalog.
  def to_s
    self[:name] + ' ' + self[:version]
  end

  # Returns a hyperlink containing the name and version of Rassmalog.
  def to_link
    link self[:website], to_s
  end

  # throw an exception instead of returning nil
  alias [] fetch
end
