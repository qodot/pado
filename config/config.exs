import Config

# 테스트 환경에서는 LLM/Credential을 fake 모듈로 갈아끼운다.
# router는 Pado.Agent.Turn에서 Application.compile_env로 컴파일 시점에 박히고,
# credentials는 Pado.LLM.Credential.load/1이 런타임에 :credentials 매핑을 읽는다.
if config_env() == :test do
  config :pado,
    router: Pado.Test.FakeLLM,
    credentials: %{
      test_provider: {Pado.Test.FakeCredsLoader, nil}
    }
end
