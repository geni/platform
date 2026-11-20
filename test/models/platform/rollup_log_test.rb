require 'test_helper'

module Platform
  # One row per rollup run: which interval it covered, and when the run started and finished.
  # The model declares nothing, so what is worth pinning is that it maps to the table the rollup
  # task and the admin screen expect -- including the platform_ prefix, which comes from
  # Platform::ApplicationRecord rather than from anything in this class.
  class RollupLogTest < Platform::TestCase

    test 'it maps to the prefixed rollup log table' do
      assert_equal 'platform_rollup_logs', Platform::RollupLog.table_name
    end

    test 'an interval and a run window round-trip' do
      interval = Time.utc(2026, 1, 1, 12, 0, 0)
      log = Platform::RollupLog.create!(interval: interval,
                                        started_at: interval + 1.minute,
                                        finished_at: interval + 3.minutes).reload

      assert_equal interval,              log.interval
      assert_equal interval + 1.minute,   log.started_at
      assert_equal interval + 3.minutes,  log.finished_at
    end

    # A run that is still going has no finished_at, which is how an unfinished rollup is told from
    # a completed one.
    test 'a run in progress has no finish time' do
      log = Platform::RollupLog.create!(interval: Time.utc(2026, 1, 1), started_at: Time.now)

      assert_nil log.reload.finished_at
    end

    test 'nothing is required' do
      assert Platform::RollupLog.create!.persisted?
    end

    # Platform::Config.reset_all! calls #delete_all on every model in its list, this one included.
    test 'it is one of the models reset_all! clears' do
      assert_includes Platform::Config.models, Platform::RollupLog
    end

  end # class RollupLogTest
end # module Platform
