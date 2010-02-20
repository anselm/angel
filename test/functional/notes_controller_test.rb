require 'test_helper'

class NotesControllerTest < ActionController::TestCase

  test "should create note" do
    assert_difference('Note.count') do
      post :create, :note => { }
    end

    assert_redirected_to note_path(assigns(:note))
  end

end
