require 'test_helper'

# Application reviews.  One rating per user per application -- #submit_app_rating edits the
# viewer's existing rating rather than adding another -- and every change re-ranks the
# application.
class Platform::RatingsControllerTest < Platform::ControllerTestCase

  test 'submit_app_rating requires login' do
    post :submit_app_rating, params: {app_id: app.id, rating_value: 4, source_url: source_url,
                                      authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  test 'submit_app_rating records a rating' do
    login_as user

    assert_difference 'Platform::Rating.count' do
      post :submit_app_rating, params: {app_id: app.id, rating_value: 4, rating_comment: 'Good',
                                        source_url: source_url,
                                        authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url

    rating = Platform::Rating.for(app, user)
    assert_equal 4, rating.value
    assert_equal 'Good', rating.comment
    assert_equal app, rating.object
  end

  test 'submit_app_rating re-ranks the application' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: 4, source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_equal 4, app.reload.rank
  end

  # One rating per user: a second submission edits the first.
  test 'submit_app_rating replaces the viewer\'s earlier rating' do
    login_as user
    post :submit_app_rating, params: {app_id: app.id, rating_value: 4, rating_comment: 'Good',
                                      source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_no_difference 'Platform::Rating.count' do
      post :submit_app_rating, params: {app_id: app.id, rating_value: 2, rating_comment: 'Less good',
                                        source_url: source_url,
                                        authenticity_token: form_authenticity_token}
    end

    rating = Platform::Rating.for(app, user)
    assert_equal 2, rating.value
    assert_equal 'Less good', rating.comment
  end

  test 'submit_app_rating stores a blank comment as nothing' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: 4, rating_comment: '',
                                      source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_nil Platform::Rating.for(app, user).comment
  end

  # Zero to five.  The bound matters because #update_rank! averages these into the rank column
  # that orders the application directory.
  test 'submit_app_rating refuses a value above five' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: 6, source_url: source_url,
                                      authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
    assert_match 'Invalid application rating value', flash[:trfe]

    assert_nil Platform::Rating.for(app, user).value
  end

  test 'submit_app_rating refuses a negative value' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: -1, source_url: source_url,
                                      authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
    assert_match 'Invalid application rating value', flash[:trfe]
  end

  test 'submit_app_rating accepts zero' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: 0, source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_equal 0, Platform::Rating.for(app, user).value
  end

  test 'submit_app_rating accepts five' do
    login_as user

    post :submit_app_rating, params: {app_id: app.id, rating_value: 5, source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_equal 5, Platform::Rating.for(app, user).value
  end

  test 'submit_app_rating records nothing over GET' do
    login_as user

    assert_no_difference 'Platform::Rating.count' do
      get :submit_app_rating, params: {app_id: app.id, rating_value: 4, source_url: source_url}
    end

    assert_redirected_to source_url
  end

  test 'submit_app_rating on an application that does not exist' do
    login_as user

    assert_raises ActiveRecord::RecordNotFound do
      post :submit_app_rating, params: {app_id: 0, rating_value: 4,
                                        authenticity_token: form_authenticity_token}
    end
  end

  ##########################################################################
  #### delete_app_rating
  ##########################################################################

  test 'delete_app_rating removes the viewer\'s rating' do
    login_as user
    rating = Platform::Rating.create!(object: app, user: user, value: 4)

    assert_difference 'Platform::Rating.count', -1 do
      post :delete_app_rating, params: {rating_id: rating.id, source_url: source_url,
                                        authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
  end

  test 'delete_app_rating re-ranks the application' do
    login_as user
    app.update!(rank: 4)
    rating = Platform::Rating.create!(object: app, user: user, value: 4)

    post :delete_app_rating, params: {rating_id: rating.id, source_url: source_url,
                                      authenticity_token: form_authenticity_token}

    assert_equal 0, app.reload.rank
  end

  test 'delete_app_rating will not remove somebody else\'s rating' do
    rating = Platform::Rating.create!(object: app, user: create_user('Reviewer'), value: 4)
    login_as user

    assert_no_difference 'Platform::Rating.count' do
      post :delete_app_rating, params: {rating_id: rating.id, source_url: source_url,
                                        authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_match 'Invalid application rating', flash[:trfe]
  end

  test 'delete_app_rating removes nothing over GET' do
    login_as user
    rating = Platform::Rating.create!(object: app, user: user, value: 4)

    assert_no_difference 'Platform::Rating.count' do
      get :delete_app_rating, params: {rating_id: rating.id, source_url: source_url}
    end

    assert_redirected_to source_url
  end

  test 'delete_app_rating on a rating that does not exist' do
    login_as user

    assert_raises ActiveRecord::RecordNotFound do
      post :delete_app_rating, params: {rating_id: 0, authenticity_token: form_authenticity_token}
    end
  end

private

  def source_url
    'http://test.host/platform/apps/1'
  end

end # class Platform::RatingsControllerTest
