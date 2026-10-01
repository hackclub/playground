# Redeeming a goal. The participant confirms where it
# ships, starting from their Hack Club Auth address; every field is editable.
# Eligibility and hours are checked again on submit.
class RedemptionsController < ApplicationController
  layout "app"
  before_action :require_login
  before_action :no_store
  before_action :set_goal
  before_action :check_can_redeem

  def new
    @addresses = Array(@identity["addresses"])
    chosen = @addresses.find { it["id"] == params[:address] } || @addresses.find { it["primary"] } || @addresses.first
    @details = chosen ? ShippingDetails.from_hca(chosen) : ShippingDetails.new(first_name: @identity["first_name"], last_name: @identity["last_name"])
    @chosen_id = chosen&.dig("id")
  end

  def create
    @details = ShippingDetails.from_params(params.require(:shipping))
    unless @details.valid?
      @addresses = Array(@identity["addresses"])
      return render :new, status: :unprocessable_entity
    end
    current_user.redemptions.create!(goal_key: @goal.key, address: @details.to_h)
    redirect_to dashboard_path, notice: "#{@goal.name} redeemed! we'll ship it soon."
  rescue ActiveRecord::RecordInvalid => e
    back(e.record.errors.full_messages.to_sentence)
  rescue ActiveRecord::RecordNotUnique
    back("you already redeemed the #{@goal.name}")
  end

  private

  def set_goal = @goal = Goal.find(params[:goal_key]) || raise(ActionController::RoutingError, "no such goal")

  def check_can_redeem
    @identity = HackClubAuth.for(current_user).refresh_user!
    current_user.reload
    return back("verify your identity first") unless current_user.eligible?
    return back("this account is banned") if current_user.banned?
    return back("you already redeemed the #{@goal.name}") if current_user.redemptions.exists?(goal_key: @goal.key)
    back("you need #{@goal.hours} approved hours") if current_user.hours.approved_seconds < @goal.seconds
  end

  def back(message) = redirect_to(dashboard_path, alert: message)
end
