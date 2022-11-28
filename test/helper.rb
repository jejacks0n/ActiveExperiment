# frozen_string_literal: true

# require "active_support/testing/strict_warnings"
require "minitest/mock"
require "simplecov"

SimpleCov.start do
  add_filter "test/"
end

require "active_experiment"

GlobalID.app = "ae"
ActiveExperiment.logger = Logger.new(nil)
ActiveExperiment::Base.default_rollout = ActiveExperiment::Rollouts::BaseRollout.new(nil)

require "support/log_helpers"
require "support/global_id_object"

require "active_support/testing/autorun"
# require_relative "../../tools/test_common"
