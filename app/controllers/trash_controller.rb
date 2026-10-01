# The desktop icons a signed-in participant has dragged into the trash, so the
# trash follows them from one browser to the next. The desktop sends the whole
# list after each change. It keeps a visitor's trash in the browser instead.
# When the banana peel itself moves, it also says whether the peel is out.
class TrashController < ApplicationController
  def update
    return head :unauthorized unless current_user
    icons = Array(params[:icons]).map(&:to_s).reject { it.blank? || it.length > 64 }.uniq.first(32)
    changes = { desktop_trash: icons }
    changes[:banana_peel_out] = ActiveModel::Type::Boolean.new.cast(params[:banana_peel_out]) if params.key?(:banana_peel_out)
    current_user.update!(changes)
    head :no_content
  end
end
