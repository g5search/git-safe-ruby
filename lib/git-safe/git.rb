module GitSafe
  class Git
    attr_reader :options

    def initialize(options)
      @options = options
    end
  end
end