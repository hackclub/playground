# The desktop's scripts are not yet nonced, so script-src stays open. These
# directives shut off plugins, <base> hijacking, and framing by other sites.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :self
  end
end
