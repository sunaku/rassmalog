# project information
#--
# Copyright 2006 Suraj N. Kurapati
# See the file named LICENSE for details.

Rassmalog = {
  :name     => 'Rassmalog',
  :version  => '9.0.1',
  :release  => '2007-12-09',
  :website  => 'http://rassmalog.rubyforge.org'
}

class << Rassmalog
  # Returns the name and version of Rassmalog.
  def to_s
    self[:name] + ' ' + self[:version]
  end

  # Returns a hyperlink containing the name and version of Rassmalog.
  def to_link
    link self[:url], to_s
  end
end
