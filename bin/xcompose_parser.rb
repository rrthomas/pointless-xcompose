#!/usr/bin/env ruby1.8
require 'optparse'
require 'ostruct'
require 'log4r'
include Log4r
require File.dirname(__FILE__) + '/keysymdef.rb'
include Keysymdef

# Parser for XCompose compose definitions.
#
# TODO: - includes
#       - "\nnn" description format
class XComposeParser
  attr_accessor :file, :parsed_lines, :logger

  # class MapConflict < StandardError
  #   def initialize(parser, l1, l2)
  #   end
  # end
  # class MapPrefixConflict < StandardError
  #   def initialize(parser, l1, l2)
  #   end
  # end
  # class MapDuplicate < StandardError
  #   def initialize(parser, l1, l2)
  #   end
  # end


  def initialize(file, logger=nil)
    if not file.respond_to? :read
      file = File.open(file.to_str, 'r')
    end
    @file = file

    if logger
      @logger = Logger.new(logger.fullname + '::' + \
                           "parser:#{@file.path}")
    else
      @logger = Logger.new("parser:#{@file.path}")
      @logger.outputters << Outputter.stdout
      @logger.level = DEBUG
    end
    @parsed_lines = []
    self.parse
  end

  class ParseError < StandardError
    def initialize(file)
      super("Parse error at file #{@file.path}:#{@file.lineno}.")
    end
  end

  # Parse the file and fill @parsed_lines.
  def parse
    @file.seek 0
    @file.each_line do |line|

      if line.match(/^#/)
        @logger.debug("Skipped comment at line #{@file.lineno}")
      elsif line.match(/^\s*$/)
        @logger.debug("Skipped blank line at line #{@file.lineno}")
      elsif line.match(/^\s*include/)
        @logger.warn("Skipped include at line #{@file.lineno}")
      elsif line.index(':')
        @parsed_lines[@file.lineno] = self.class.parse_line(line)
        if not @parsed_lines[@file.lineno]
          raise ParseError.new(@file)
        end
      else
        raise ParseError.new(@file)
      end
    end
  end

  # Parse a singe XCompose line.
  #
  # Returns a hash with :map, :definition, :description, and :comment.
  def self.parse_line(line)
    map_side, definition_side = line.split ':'
    definition, comment = definition_side.split '#'
    defchar, defdesc = definition.split(/\s/).reject {|s| s.empty?}

    parsed = {}

    parsed[:map] = map_side.split(/\s/).reject {|s| s.empty?}.each do |s|
      s.strip
    end

    defin = defchar.strip.sub(/^["']/,'').sub(/["']$/,'')
    # unquote definition
    if defin == '\\"'
      parsed[:definition] = '"'
    elsif defin == '\\\\'
      parsed[:definition] = '\\'
    else
      parsed[:definition] = defin
    end

    parsed[:description] = defdesc.strip if defdesc
    parsed[:comment] = comment.strip if comment

    parsed
  end


  class InvalidCodepoint < StandardError
    def initialize(invcd)
      super(invcd + " doesn't look like a codepoint")
    end
  end

  class UnknownKeysymname < StandardError
    def initialize(keysymname)
      super(format("Couldn't find keysym name `%s' in database", keysymname))
    end
  end

  class DescriptionConflict < StandardError
    def initialize(parsed_line)
      super(format("Description `%s' doesn't match definition `%s'",
                   parsed_line[:description],
                   parsed_line[:definition]))

    end
  end

  # Utility function to convert a codepoint like U+nnn or Unnnn to
  # UTF-8 string.
  def self.codepoint_to_unichar(codepoint)
    # get an integer out of codepoint
    if not codepoint.kind_of? Integer
      if codepoint.respond_to? :to_str
        if m=codepoint.match(/^U\+?([0-9abcdef]+)$/i)
          codepoint = m[1].to_i(16)
        else
          raise InvalidCodepoint.new(codepoint)
        end
      else
        codepoint = codepoint.to_i
      end
    end

    [codepoint].pack('U')
  end

  # Checks whether a parsed line's description matches its definition.
  def self.validate_desc(parsed_line)
    desc, defin = parsed_line[:description], parsed_line[:definition]

    return true if (not desc or not defin)
    if desc.match(/^U\+?[0-9A-F]+$/i) # if unicode description
      if (defin != codepoint_to_unichar(desc))
        raise DescriptionConflict.new(parsed_line)
      else
        return true
      end
    else # keysymname description
      keysymval = Keysyms[desc]
      if not  keysymval
        raise UnknownKeysymname.new(desc)
      elsif defin != keysymval
        raise DescriptionConflict.new(parsed_line)
      else
        return true
      end
    end
  end

  def validate_descs()
    valid=true
    0.upto(@parsed_lines.size) do |i|
      next if not @parsed_lines[i]
      begin
        self.class.validate_desc(@parsed_lines[i])
        @logger.debug("#{i}: description valid.")
      rescue UnknownKeysymname, DescriptionConflict, InvalidCodepoint => ex
        @logger.error("#{i}: #{ex.message}")
        valid = false
      end
    end
    return valid
  end

end

if __FILE__ == $0
  options = OpenStruct.new
  OptionParser.new {|op|
    op.banner = "Usage: #{$0} [options] <Compose files...>"
    op.on('v', '--verbose', 'Increase verbosity') do |v|
      options.verbose = v
    end
  }.parse!

  exit 1 if not ARGV[0]
  ARGV.each do |fpath|
    if not File.readable? fpath
      $stderr.puts "Cannot read file #{fpath}"
      exit 1
    end
  end

  l = Logger.new('xcompose')
  if options.verbose
    l.level=DEBUG
  else
    l.level=INFO
  end
  l.outputters << Outputter.stdout


  all_valid = true
  ARGV.each do |fpath|
    p = XComposeParser.new(fpath, l)

    if p.validate_descs
      p.logger.info("Descriptions ok.")
    else
      p.logger.error("Description errors.")
      all_valid=false if all_valid
    end
  end

  if all_valid
    exit 0
  else
    exit 1
  end
end
