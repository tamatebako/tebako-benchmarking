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

      class_option :repetitions,
                   type: :array, aliases: "-r",
                   required: false,
                   desc: "Repetitions to run (array of numbers or 'I' for a single run of original application)",
                   default: ["1"]

      class_option :verbose, type: :boolean, aliases: "-v", default: false,
                             desc: "Print benchmarking data for each repetition value"

      desc "compare", "Compare execution metrics of two commands"
      method_option :first, type: :string, required: true, aliases: "-f",
                            desc: "The first command"
      method_option :second, type: :string, required: true, aliases: "-s",
                             desc: "The second command"

      def compare
        exit 1 if (repetitions = preprocess).nil?
        cmd1 = options["first"]
        cmd2 = options["second"]
        exit 1 if repetitions[0] > 1 && !(Tebako::Benchmarking.test_cmd(cmd1) && Tebako::Benchmarking.test_cmd(cmd2))

        do_compare(cmd1, cmd2, repetitions, options["verbose"])
      end

      desc "measure", "Measure execution metrics for a command"
      method_option :cmd, type: :string, aliases: "-c", required: true,
                          desc: "Command to benchmark"
      def measure
        exit 1 if (repetitions = preprocess).nil?
        cmd = options["cmd"]
        exit 1 if repetitions[0] > 1 && Tebako::Benchmarking.test_cmd(cmd)

        mea = iterate(cmd, repetitions, options["verbose"])
        print_results(mea)
      end

      default_task :help

      def self.exit_on_failure?
        true
      end
      # rubocop:disable Metrics/BlockLength
      no_commands do
        def do_compare(cmd1, cmd2, repetitions, verbose)
          mea1 = iterate(cmd1, repetitions, verbose)
          mea2 = iterate(cmd2, repetitions, verbose)
          print_comparison(cmd1, cmd2, mea1, mea2)
        end

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
          return [0] if options["repetitions"] == ["I"]

          repetitions = options["repetitions"].map(&:to_i)
          repetitions.sort!

          return repetitions unless repetitions[0] < 1

          puts "Repetitions must be positive integers or I (for a single run of original application)"
          nil
        end

        def print_comparison_headers(cmd1, cmd2)
          l1 = cmd1.length
          l2 = cmd2.length

          puts

          header0 = format("%<key>-15s| %<value1>-#{l1}s| %<value2>-#{l2}s",
                           key: "Repetitions",
                           value1: "Total time",
                           value2: "Total time")
          puts header0
          puts format("%<key>-15s| %<value1>-#{l1}s| %<value2>-#{l2}s",
                      key: "",
                      value1: cmd1.to_s,
                      value2: cmd2.to_s)

          puts "-" * header0.length
        end

        def print_comparison(cmd1, cmd2, mea1, mea2)
          rows = mea1.keys.zip(mea1.values, mea2.values).map do |r, m1, m2|
            format("%<key>-15s| %<value1>-#{cmd1.length}s| %<value2>-#{cmd2.length}s",
                   key: (r.zero? ? 1 : r),
                   value1: m1["total"],
                   value2: m2["total"])
          end

          puts print_comparison_headers(cmd1, cmd2)
          puts rows
        end

        def print_results(mea)
          header = format("%<key>-15s %<value>-15s", key: "Repetitions", value: "Total time")
          separator = "-" * header.length
          rows = mea.map do |r, m|
            format("%<key>-15s %<value>-20s", key: (r.zero? ? 1 : r), value: m["total"])
          end

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

      def measure(package, rpt, verbose)
        print "Collecting data for '#{package}' with #{rp_print_v(rpt)} repetition#{rp_print_e(rpt)} ... "
        stdout_str, stderr_str, status = do_measure(package, rpt, verbose)
        mtr = nil
        if status.success?
          puts "OK"
          mtr = metrics(stderr_str, verbose)
        else
          puts "Failed"
          err_bench(stdout_str, stderr_str)
        end
        mtr
      end

      def rp_print_v(repetitions)
        repetitions.zero? ? 1 : repetitions
      end

      def rp_print_e(repetitions)
        repetitions < 2 ? "" : "s"
      end

      def metrics(stderr_str, verbose)
        metrics = parse_time_output(stderr_str)
        metrics["total"] = metrics["user"].to_f + metrics["sys"].to_f
        print_map_as_table(metrics) if verbose
        metrics
      end

      def do_measure(package, repetitions, verbose)
        cmd = if repetitions.zero?
                "#{package} > /dev/null"
              else
                "#{package} #{repetitions} > /dev/null"
              end
        Open3.capture3("/usr/bin/time", verbose ? "-lp" : "-p", "sh", "-c", cmd)
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
