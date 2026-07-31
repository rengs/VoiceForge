from backend.agent.router import Intent, IntentRouter


def test_plain_dictation_routes_to_input() -> None:
    decision = IntentRouter().route("今天完成智能采油项目方案编制。")
    assert decision.intent == Intent.INPUT
    assert decision.content == "今天完成智能采油项目方案编制。"


def test_rewrite_uses_selected_text() -> None:
    decision = IntentRouter().route(
        "把这句话改成科技项目申报语言。",
        selected_text="我们要把采油做得更智能。",
    )
    assert decision.intent == Intent.REWRITE
    assert decision.source == "selection"
    assert decision.content == "我们要把采油做得更智能。"


def test_rewrite_falls_back_to_recent_input() -> None:
    decision = IntentRouter().route(
        "把下面内容优化一下语言。",
        recent_input="今天完成智能采油项目方案编制。",
    )
    assert decision.intent == Intent.REWRITE
    assert decision.source == "memory"


def test_supported_intents() -> None:
    router = IntentRouter()
    assert router.route("翻译成英文").intent == Intent.TRANSLATE
    assert router.route("总结这段文字").intent == Intent.SUMMARIZE
    assert router.route("帮我写一段介绍").intent == Intent.GENERATE
    assert router.route("生成一段 Python 代码").intent == Intent.CODE
