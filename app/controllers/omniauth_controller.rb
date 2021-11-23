class OmniauthController < ApplicationController
  before_action :redirect_to_login_if_connection_aborted, only: [:callback]
  before_action :securely_retrieve_fci, only: [:merge, :merge_with_existing_account, :merge_with_new_account]

  PROVIDERS = ['google', 'microsoft', 'yahoo', 'sipf', 'tatou']

  def login
    provider = provider_param
    # already checked in routes.rb but brakeman complains
    if PROVIDERS.include?(provider)
      redirect_to OmniAuthService.authorization_uri(provider)
    else
      raise "Invalid authentication method '#{provider} (should be any of #{PROVIDERS})"
    end
  end

  def callback
    provider = provider_param
    fci = OmniAuthService.find_or_retrieve_user_informations(provider, params[:code])

    if fci.user.nil?
      preexisting_unlinked_user = User.find_by(email: fci.email_france_connect.downcase)

      if preexisting_unlinked_user.nil?
        fci.associate_user!(fci.email_france_connect)
        connect_user(provider, fci.user)
      else
        redirect_to omniauth_merge_path(provider, fci.create_merge_token!)
      end
    else
      user = fci.user

      if user.can_france_connect?
        fci.update(updated_at: Time.zone.now)
        connect_user(provider, user)
      else
        fci.destroy
        redirect_to new_user_session_path, alert: t('errors.messages.omni_auth.forbidden_html', reset_link: new_user_password_path, provider: t("errors.messages.omni_auth.#{provider}"))
      end
    end

  rescue Rack::OAuth2::Client::Error => e
    Rails.logger.error e.message
    redirect_error_connection(provider)
  end

  def merge
    @provider = provider_param
  end

  def merge_with_existing_account
    user = User.find_by(email: sanitized_email_params)
    provider = provider_param

    if user.valid_for_authentication? { user.valid_password?(password_params) }
      if !user.can_france_connect?
        flash.alert = "#{user.email} en tant que admnistrateur ou instructeur, ne peut utiliser une connection #{provider}"

        render js: ajax_redirect(root_path)
      else
        @fci.update(user: user)
        @fci.delete_merge_token!

        flash.notice = "Les comptes #{provider} et #{APPLICATION_NAME} sont à présent fusionnés"
        connect_user(provider, user)
      end
    else
      flash.alert = 'Mauvais mot de passe'

      render js: helpers.render_flash
    end
  end

  def merge_with_new_account
    user = User.find_by(email: sanitized_email_params)
    provider = provider_param

    if user.nil?
      @fci.associate_user!(sanitized_email_params)
      @fci.delete_merge_token!

      flash.notice = "Les comptes #{provider} et #{APPLICATION_NAME} sont à présent fusionnés"
      connect_user(provider, @fci.user)
    else
      @email = sanitized_email_params
      @merge_token = merge_token_params
    end
  end

  private

  def redirect_to_login_if_connection_aborted
    if params[:code].blank?
      redirect_to new_user_session_path
    end
  end

  def redirect_error_connection(provider)
    flash.alert = t("errors.messages.omni_auth.connexion", provider: t("errors.messages.omni_auth.#{provider}"))
    redirect_to(new_user_session_path)
  end

  private

  def securely_retrieve_fci
    @fci = FranceConnectInformation.find_by(merge_token: merge_token_params)

    if @fci.nil? || !@fci.valid_for_merge?
      flash.alert = 'Le lien que vous suivez a expiré, veuillez recommencer la procédure.'

      respond_to do |format|
        format.html { redirect_to root_path }
        format.js { render js: ajax_redirect(root_path) }
      end
    end
  end

  def connect_user(provider, user)
    if user_signed_in?
      sign_out :user
    end

    sign_in user

    user.update_attribute('loged_in_with_france_connect', User.loged_in_with_france_connects.fetch(provider))

    redirection_location = stored_location_for(current_user) || root_path(current_user)

    respond_to do |format|
      format.html { redirect_to redirection_location }
      format.js { render js: ajax_redirect(root_path) }
    end
  end

  def provider_param
    params[:provider]
  end

  def merge_token_params
    params[:merge_token]
  end

  def password_params
    params[:password]
  end

  def sanitized_email_params
    params[:email]&.gsub(/[[:space:]]/, ' ')&.strip&.downcase
  end
end