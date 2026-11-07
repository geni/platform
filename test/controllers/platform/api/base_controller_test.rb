require 'test_helper'

# Covers the three things on Platform::Api::BaseController that Rails 5-7 broke and that nothing in
# this gem's suite reached, because its only API subclass -- Platform::Api::AppsController -- is not
# routed in config/routes.rb.  That is why all three were found from a host app instead.
#
# These are unit tests on purpose: there is no route to drive a request through, and the contract
# each one has is with its caller rather than with a response body.
class Platform::Api::BaseControllerTest < Platform::ControllerTestCase
  tests Platform::Api::AppsController

  ForbiddenError    = Platform::Api::BaseController::ForbiddenError
  UnauthorizedError = Platform::Api::BaseController::UnauthorizedError
  BadRequestError   = Platform::Api::BaseController::BadRequestError

  ##########################################################################
  #### render_exception -- the API's error envelope
  ##########################################################################

  test 'render_exception answers an ApiError with its own status and message' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'no entry'}},
      status: :forbidden
    )

    @controller.send(:render_exception, ForbiddenError.new('no entry'))
  end

  test 'render_exception retypes an UnauthorizedError as an OAuthException' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'OAuthException', 'message' => 'Invalid access token'}},
      status: :unauthorized
    )

    @controller.send(:render_exception, UnauthorizedError.new('Invalid access token'))
  end

  test 'render_exception answers a RecordNotFound as 404 without leaking the message' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'Not Found'}},
      status: :not_found
    )

    @controller.send(:render_exception, ActiveRecord::RecordNotFound.new("Couldn't find Profile with id 7"))
  end

  test 'render_exception answers an unexpected exception as a 500' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'kaboom'}},
      status: :internal_server_error
    )

    @controller.send(:render_exception, RuntimeError.new('kaboom'))
  end

  test 'render_exception clears only_list so the envelope is not wrapped in an array' do
    params = {only_list: '1'}
    @controller.stubs(:params).returns(params)
    @controller.stubs(:render_response)

    @controller.send(:render_exception, BadRequestError.new('bad'))

    assert_nil params[:only_list]
  end

  # This gem renders API errors and does not log them -- a6f7aa5's intent.  The host app owns the
  # `rescue_from` that calls #render_exception and whatever logging it wants in front of it, so
  # neither a logger nor a logging policy should reappear here.
  test 'the gem renders API errors without logging them' do
    %i[log_exception should_log_error?].each do |name|
      assert_not @controller.respond_to?(name, true),
                 "#{name} is the host app's; exception logging does not belong in this gem"
    end

    assert @controller.respond_to?(:render_exception, true)
  end

  ##########################################################################
  #### parse_time / end_time -- Rails 7 removed to_s's format argument
  ##########################################################################

  test 'parse_time renders a timestamp in the :db format' do
    assert_equal '2026-03-04 05:06:07', @controller.send(:parse_time, '2026-03-04 05:06:07', 'unused')
  end

  # to_fs(:db) would answer the UTC instant here.  These strings are interpolated into SQL against
  # :local columns by #time_clause, so the wall clock has to survive the round trip.
  test 'parse_time keeps the local wall clock rather than converting to UTC' do
    parsed = @controller.send(:parse_time, '2026-07-04 23:30:00', 'unused')

    assert_equal '2026-07-04 23:30:00', parsed
    assert_not_equal Time.parse('2026-07-04 23:30:00').utc.strftime('%Y-%m-%d %H:%M:%S'), parsed,
                     'a UTC rendering would shift the window by the zone offset'
  end

  test 'parse_time answers the default for nil' do
    assert_equal 'the-default', @controller.send(:parse_time, nil, 'the-default')
  end

  test 'parse_time understands today and yesterday' do
    assert_equal Date.today.to_s,     @controller.send(:parse_time, 'today',     'unused')
    assert_equal Date.yesterday.to_s, @controller.send(:parse_time, 'YESTERDAY', 'unused')
  end

  test 'end_time defaults to tomorrow' do
    @controller.stubs(:params).returns({})

    assert_equal Date.tomorrow.to_s, @controller.send(:end_time)
  end

  # The pair a host app's #time_clause interpolates into SQL (`time_clause` itself is the host's
  # extension, not this class's).
  test 'start_time and end_time answer the window the caller asked for' do
    @controller.stubs(:params).returns({since: '2026-01-02', until: '2026-01-03'})

    assert_equal '2026-01-02 00:00:00', @controller.send(:start_time)
    assert_equal '2026-01-03 00:00:00', @controller.send(:end_time)
  end

  test 'start_time defaults to the start of the archive' do
    @controller.stubs(:params).returns({})

    assert_equal '2007-01-01', @controller.send(:start_time)
  end

  ##########################################################################
  #### prev_page_url / next_page_url -- params is not a Hash on Rails 5+
  ##########################################################################

  # params.merge(...) answers ActionController::Parameters, and url_for calls #to_h on it, which
  # raises ActionController::UnfilteredParameters -- so any paginated response carrying a page link
  # was a 500.  Asserting url_for is handed a real Hash is what pins the fix: Parameters is not one.
  test 'prev_page_url hands url_for a Hash rather than Parameters' do
    @controller.stubs(:params).returns(ActionController::Parameters.new(:page => '3', :fields => 'name'))
    @controller.stubs(:page).returns(3)

    @controller.expects(:url_for).with do |given|
      given.is_a?(Hash) && !given.is_a?(ActionController::Parameters) &&
        given['fields'] == 'name' && given[:page] == 2
    end

    @controller.send(:prev_page_url)
  end

  test 'next_page_url hands url_for a Hash rather than Parameters' do
    @controller.stubs(:params).returns(ActionController::Parameters.new(:page => '3', :fields => 'name'))
    @controller.stubs(:page).returns(3)

    @controller.expects(:url_for).with do |given|
      given.is_a?(Hash) && !given.is_a?(ActionController::Parameters) && given[:page] == 4
    end

    @controller.send(:next_page_url)
  end

end # class Platform::Api::BaseControllerTest
