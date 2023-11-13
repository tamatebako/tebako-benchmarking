#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright (c) 2023 [Ribose Inc](https://www.ribose.com).
# All rights reserved.
# This file is a part of tebako
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require "fileutils"
require "open3"
require "thor"
require "yaml"

# Tebako benchmarking tool
# Implementation of command-line interface
module Tebako
  module Benchmarking
    OPTIONS_FILE = ".tebako-benchmarking.yml"
    # Tebako packager front-end
    class Cli < Thor
      package_name "Tebako benchmarking"

      desc "measure", "Measure execution metrics of a Tebako package"
      method_option :package, type: :string, aliases: "-p", required: true,
                              desc: "Tebako package to benchmark"

      method_option :repetitions, type: :array, aliases: "-r", required: true,
                                  desc: "Repetitions to run (array of positive integers)", default: ["1"]
      method_option :verbose, type: :boolean, aliases: "-v", default: false,
                              desc: "Print benchmarking data for each repetition value"
      def measure
        exit 1 if (repetitions = preprocess).nil?
        package = options["package"]
        exit 1 unless repetitions[0] == 1 || Tebako::Benchmarking.test_cmd(package)

        mea = iterate(package, repetitions, options["verbose"])
        print_results(mea)
      end

      default_task :help

      def self.exit_on_failure?
        true
      end
      # rubocop:disable Metrics/BlockLength
      no_commands do
        def iterate(package, repetitions, verbose)
          mea = {}

          repetitions.each do |r|
            mea[r] = Tebako::Benchmarking.measure(package, r, verbose)
            exit 1 if mea[r].nil?
          end

          mea
        end

        def options
          original_options = super

          return original_options unless File.exist?(OPTIONS_FILE)

          defaults = ::YAML.load_file(OPTIONS_FILE) || {}
          Thor::CoreExt::HashWithIndifferentAccess.new(defaults.merge(original_options))
        end

        def preprocess
          repetitions = options["repetitions"].map(&:to_i)
          repetitions.sort!

          return repetitions unless repetitions[0] < 1

          puts "Repetitions must be positive integers"
          nil
        end

        def print_results(mea)
          header = format("%<key>-15s %<value>-15s", key: "Repetitions", value: "Total time")
          separator = "-" * header.length
          rows = mea.map { |r, m| format("%<key>-15s %<value>-20s", key: r, value: m["total"]) }

          puts
          puts header
          puts separator
          puts rows
        end
      end
      # rubocop:enable Metrics/BlockLength
    end

    class << self
      def err_bench(stdout_str, stderr_str)
        puts <<~ERROR_MESSAGE
          ----- Stdout -----
          #{stdout_str}
          ----- Stderr -----
          #{stderr_str}
          ------------------
        ERROR_MESSAGE
      end

      def err_parse(msg, output)
        puts <<~ERROR_MESSAGE
          Error parsing time output: #{msg}
          Output:
          #{output}
        ERROR_MESSAGE
      end

      def measure(package, repetitions, verbose)
        print "Collecting data for '#{package}' with #{repetitions} repetitions ... "
        stdout_str, stderr_str, status = do_measure(package, repetitions)
        if status.success?
          puts "OK"
          metrics = parse_time_output(stderr_str)
          metrics["total"] = metrics["user"].to_f + metrics["sys"].to_f
          print_map_as_table(metrics) if verbose
        else
          puts "Failed"
          err_bench(stdout_str, stderr_str)
        end
        status.success? ? metrics : nil
      end

      def do_measure(package, repetitions)
        cmd = "#{package} #{repetitions} > /dev/null"
        Open3.capture3("/usr/bin/time", "-l", "-p", "sh", "-c", cmd)
      end

      def print_map_as_table(map)
        header = format("%<key>-40s %<value>-20s", key: "Key", value: "Value")
        separator = "-" * header.length
        rows = map.map { |key, value| format("%<key>-40s %<value>-20s", key: key, value: value) }

        puts header
        puts separator
        puts rows
      end

      def parse_time_output(output)
        begin
          lines = output.split("\n")
          parsed_output = {}
          lines.each_with_index do |line, index|
            line.strip!
            l1, l2 = line.split(/\s+/, 2)
            parsed_output[index < 3 ? l1.strip : l2.strip] = index < 3 ? l2.strip : l1.strip
          end
        rescue StandardError => e
          err_parse(e.message, output)
        end

        parsed_output
      end

      def test_cmd(cmd)
        print "Testing validity of 'sh -c \"#{cmd} 1\"' command ... "
        stdout2e, status = Open3.capture2e("sh", "-c", "#{cmd} 1")

        puts status.success? ? "ok" : "failure"

        unless status.success?
          puts "Command sh -c \"#{cmd}\" failed: #{status}"
          puts "Output:"
          puts stdout2e
        end
        status.success?
      end
    end
  end
end
