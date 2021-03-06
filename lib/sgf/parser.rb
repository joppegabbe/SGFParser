require 'stringio'

module SGF

  #The parser returns a SGF::Collection representation of the SGF file
  #parser = SGF::Parser.new
  #collection = parser.parse sgf_in_string_form
  class Parser

    NEW_NODE = ";"
    BRANCHING = %w{( )}
    END_OF_FILE = false
    NODE_DELIMITERS = [NEW_NODE].concat(BRANCHING).concat([END_OF_FILE])
    PROPERTY = %w([ ])
    LIST_IDENTITIES = %w(AW AB AE AR CR DD LB LN MA SL SQ TR VW TB TW)

    # This takes as argument an SGF and returns an SGF::Collection object
    # It accepts a local path (String), a stringified SGF (String),
    # or a file handler (File).
    # The second argument is optional, in case you don't want this to raise errors.
    # You probably shouldn't use it, but who's gonna stop you?
    def parse sgf, strict_parsing = true
      error_checker = strict_parsing ? StrictErrorChecker.new : LaxErrorChecker.new
      @sgf_stream = SgfStream.new(sgf, error_checker)
      @assembler = CollectionAssembler.new
      until @sgf_stream.eof?
        case @sgf_stream.next_character
          when "(" then @assembler.open_branch
          when ";" then
            parse_node_data
            @assembler.create_node_with_properties @node_properties
          when ")" then @assembler.close_branch
          else next
        end
      end
      @assembler.collection
    end

    private

    def parse_node_data
      @node_properties = {}
      while still_inside_node?
        identity = @sgf_stream.read_token IdentityToken.new
        property_format = property_token_type identity
        property = @sgf_stream.read_token property_format
        @node_properties[identity] = property
      end
    end

    def still_inside_node?
      !NODE_DELIMITERS.include?(@sgf_stream.peek_skipping_whitespace)
    end
    
    def property_token_type identity
      case identity.upcase
        when "C" then CommentToken.new
        when *LIST_IDENTITIES then MultiPropertyToken.new
        else GenericPropertyToken.new
      end
    end
  end

  class CollectionAssembler
    attr_reader :collection

    def initialize
      @collection = Collection.new
      @current_node = @collection.root
      @branches = []
    end

    def open_branch
      @branches.unshift @current_node
    end

    def close_branch
      @current_node = @branches.shift
    end

    def create_node_with_properties properties
      node = SGF::Node.new
      @current_node.add_children node
      @current_node = node
      @current_node.add_properties properties
    end
  end

  class IdentityToken
    def still_inside? char, token_so_far, sgf_stream
      char != "["
    end

    def transform token
      token.gsub "\n", ""
    end
  end

  class CommentToken
    def still_inside? char, token_so_far, sgf_stream
      char != "]" || (char == "]" && token_so_far[-1..-1] == "\\")
    end

    def transform token
      token.gsub "\\]", "]"
    end
  end

  class MultiPropertyToken
    def still_inside? char, token_so_far, sgf_stream
      return true if char != "]"
      sgf_stream.peek_skipping_whitespace == "["
    end

    def transform token
      token.gsub("][", ",").split(",")
    end
  end

  class GenericPropertyToken
    def still_inside? char, token_so_far, sgf_stream
      char != "]"
    end
    
    def transform token
      token
    end
  end

  class StrictErrorChecker
    def check_for_errors_before_parsing string
      unless string[/\A\s*\(\s*;/]
        msg = "The first two non-whitespace characters of the string should be (;"
        msg << " but they were #{string[0..1]} instead."
        raise(SGF::MalformedDataError, msg)
      end
    end
  end

  class LaxErrorChecker
    def check_for_errors_before_parsing string
      # just look the other way
    end
  end

  class SgfStream
    attr_reader :stream

    def initialize sgf, error_checker
      sgf = sgf.read if sgf.instance_of?(File)
      sgf = File.read(sgf) if File.exist?(sgf)
      error_checker.check_for_errors_before_parsing sgf
      @stream = StringIO.new clean(sgf), 'r'
    end

    def eof?
      @stream.eof?
    end

    def next_character
      !@stream.eof? && @stream.sysread(1)
    end

    def read_token format
      property = ""
      while char = next_character and format.still_inside? char, property, self
        property << char
      end
      format.transform property
    end

    def peek_skipping_whitespace
      while char = next_character
        next if char[/\s/]
        break
      end
      rewind if char
      char
    end

    private

    def rewind
      @stream.pos -= 1
    end

    def clean sgf
      sgf.gsub! "\\\\n\\\\r", ''
      sgf.gsub! "\\\\r\\\\n", ''
      sgf.gsub! "\\\\r", ''
      sgf.gsub! "\\\\n", ''
      sgf
    end
  end
end
