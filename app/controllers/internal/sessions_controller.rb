# frozen_string_literal: true

module Internal
  class SessionsController < ::ApplicationController
    layout "internal"

    helper_method :current_operator

    def new
      redirect_to internal_path if current_operator
    end

    def create
      credential = Workspace::Models::OperatorCredential.find_for_login(login_params[:username])

      if credential&.authenticate(login_params[:password])
        credential.update!(failed_login_attempts: 0, last_sign_in_at: Time.current)
        reset_session
        session[:operator_id] = credential.operator_id
        redirect_to internal_path, notice: "Signed in"
      else
        credential&.increment!(:failed_login_attempts)
        flash.now[:alert] = "Invalid username or password"
        render :new, status: :unauthorized
      end
    end

    def destroy
      reset_session
      redirect_to login_path, notice: "Signed out", status: :see_other
    end

    private

    def current_operator
      @current_operator ||= Workspace::Models::Operator.find_by(id: session[:operator_id], active: true)
    end

    def login_params
      params.permit(:username, :password)
    end
  end
end
