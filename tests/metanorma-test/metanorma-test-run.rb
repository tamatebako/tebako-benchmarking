#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems"
require "openssl"
require "open-uri"
require "net/https"

require "jing"
require "optout"

# Limit Relaton to concurrent fetches of 1
ENV["RELATON_FETCH_PARALLEL"] = "1"

unless Gem.win_platform? # because on windows we use aibika
  # This code was bundled with ruby-packer/tebako hack but is not related
  class Jing
    def self.option_builder
      @@option_builder
    end
  end

  class Optout
    def []=(name, value)
      @options[name] = value
    end
  end

  Jing.option_builder[:jar] = Optout::Option.create(:jar, "-jar",
                                                    index: 1,
                                                    validator: Optout::File.exists,
                                                    default: Jing::DEFAULT_JAR)
end

# explicitly load all dependent gems
# ruby packer cannot use gem load path correctly.
require "metanorma/cli"

# start up the CLI
Metanorma::Cli.start(ARGV)
