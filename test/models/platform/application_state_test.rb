require 'test_helper'

module Platform
  # The acts_as_state_machine workflow an application moves through on its way to being approved.
  #
  # Worth its own tests on this branch for a reason that has nothing to do with the states: the
  # gem is on a fork of acts_as_state_machine, and Platform::ApplicationRecord carries four
  # shims -- #write_inheritable_attribute, #class_inheritable_reader, #write_inheritable_hash and
  # #read_inheritable_attribute -- that exist only to give that gem the Rails 2 class-attribute
  # API it still calls.  Those shims have no other caller, so these tests are what covers them.
  class ApplicationStateTest < Platform::TestCase

    test 'an application starts out new' do
      assert_equal 'new', create_app.state
    end

    ##########################################################################
    #### The approval path
    ##########################################################################

    test 'a new application can be submitted and then approved' do
      a = create_app

      a.submit!
      assert_equal 'submitted', a.reload.state

      a.approve!
      assert_equal 'approved', a.reload.state
    end

    test 'a new application can be approved without being submitted' do
      a = create_app
      a.approve!

      assert_equal 'approved', a.reload.state
    end

    test 'a submitted application can be rejected and then resubmitted' do
      a = create_app
      a.submit!

      a.reject!
      assert_equal 'rejected', a.reload.state

      a.submit!
      assert_equal 'submitted', a.reload.state
    end

    test 'an approved application can be deprecated' do
      a = create_app
      a.approve!

      a.deprecate!

      assert_equal 'deprecated', a.reload.state
    end

    ##########################################################################
    #### Blocking
    ##########################################################################

    test 'an application can be blocked from any state before deprecation' do
      %w[new submitted approved rejected].each do |from|
        a = reach(from)

        a.block!

        assert_equal 'blocked', a.reload.state, "should be blockable from #{from}"
      end
    end

    # Unblocking returns the application to new rather than to the state it was blocked from, so
    # an approved application that is blocked has to go through approval again.
    test 'unblocking returns the application to new' do
      a = create_app
      a.approve!
      a.block!

      a.unblock!

      assert_equal 'new', a.reload.state
    end

    ##########################################################################
    #### Transitions that are not declared
    ####
    #### An undeclared transition does not raise and does not change the state -- the event is
    #### simply a no-op.
    ####
    #### What it returns is the trap.  A transition that happened returns true; one that did not
    #### returns [] -- the empty list of transitions it found to try -- and [] is truthy in Ruby.
    #### So `if app.approve!` is true either way, and the only way to tell whether an event took
    #### effect is to read #state afterwards.  Every test below therefore asserts on the state,
    #### and the return value is pinned once, on its own, so that it is visible.
    ##########################################################################

    test 'a transition that happened returns true' do
      assert_equal true, create_app.submit!
    end

    test 'a transition that did not happen returns a truthy empty array, not false' do
      a = create_app
      a.approve!

      result = a.submit!

      assert_equal [], result
      assert_equal true, !!result,
                   'so a caller testing the return value cannot tell a refused event from a successful one'
    end

    test 'an undeclared transition leaves the state alone' do
      a = create_app
      a.approve!

      a.submit!

      assert_equal 'approved', a.reload.state
    end

    test 'a deprecated application is terminal' do
      a = create_app
      a.approve!
      a.deprecate!

      a.block!
      a.submit!
      a.approve!

      assert_equal 'deprecated', a.reload.state
    end

    test 'a new application cannot be rejected or deprecated' do
      a = create_app

      a.reject!
      a.deprecate!

      assert_equal 'new', a.reload.state
    end

    test 'only a blocked application can be unblocked' do
      a = create_app

      a.unblock!

      assert_equal 'new', a.reload.state
    end

    test 'a rejected application cannot be approved directly' do
      a = reach('rejected')

      a.approve!

      assert_equal 'rejected', a.reload.state, 'it has to be resubmitted first'
    end

    ##########################################################################
    #### The Rails 2 class-attribute shims on Platform::ApplicationRecord
    ##########################################################################

    test 'the declared states and events are readable through the inheritable attribute shim' do
      states = Platform::Application.read_inheritable_attribute(:states).map { |s| s.name.to_s }

      assert_equal %w[approved blocked deprecated new rejected submitted], states.sort
    end

    test 'write_inheritable_attribute defines a class attribute with a default' do
      klass = Class.new(Platform::ApplicationRecord) { self.table_name = 'platform_applications' }
      klass.write_inheritable_attribute(:shimmed, 'value')

      assert_equal 'value', klass.shimmed
      assert_equal 'value', klass.read_inheritable_attribute(:shimmed)
    end

    test 'write_inheritable_hash defaults to an empty hash' do
      klass = Class.new(Platform::ApplicationRecord) { self.table_name = 'platform_applications' }
      klass.write_inheritable_hash(:shimmed_hash)

      assert_equal({}, klass.shimmed_hash)
    end

    test 'class_inheritable_reader defines the reader with no default' do
      klass = Class.new(Platform::ApplicationRecord) { self.table_name = 'platform_applications' }
      klass.class_inheritable_reader(:shimmed_reader)

      assert_nil klass.shimmed_reader
    end

private

    # An application in the given state, reached through the declared transitions.
    def reach(state)
      a = create_app

      case state
      when 'new'       then a
      when 'submitted' then a.tap(&:submit!)
      when 'approved'  then a.tap(&:approve!)
      when 'rejected'  then a.tap { |app| app.submit!; app.reject! }
      else raise ArgumentError, "no path to #{state}"
      end
    end

  end # class ApplicationStateTest
end # module Platform
