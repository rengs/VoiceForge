from __future__ import annotations

import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        choices=("sensevoice", "paraformer"),
        default="sensevoice",
    )
    arguments = parser.parse_args()

    if arguments.model == "sensevoice":
        from modelscope import snapshot_download

        path = snapshot_download("iic/SenseVoiceSmall")
        print(f"SenseVoiceSmall 已下载：{path}")
        return

    from funasr import AutoModel

    AutoModel(
        model="paraformer-zh",
        punc_model="ct-punc",
        disable_update=True,
        device="cpu",
    )
    print("Paraformer 与标点模型已下载。")


if __name__ == "__main__":
    main()
