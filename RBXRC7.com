import streamlit as st
import os
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.messages import HumanMessage, AIMessage
from langchain_community.chat_message_histories import ChatMessageHistory
from langchain_core.runnables.history import RunnableWithMessageHistory
import datetime

# ============================================================
# 1. Cáº¤U HĂŒNH TRANG
# ============================================================
st.set_page_config(
    page_title="RBXRC7 AI Chat",
    page_icon="watermarked_img_14795130539625529321.png",
    layout="centered"
)

BOT_AVATAR = "watermarked_img_14795130539625529321.png"

# CSS nháº¹ Ä‘á»ƒ giao diá»‡n gá»n gĂ ng, hiá»‡n Ä‘áº¡i hÆ¡n
st.markdown("""
<style>
.stChatMessage { border-radius: 14px; }
div[data-testid="stSidebarUserContent"] { padding-top: 1rem; }
</style>
""", unsafe_allow_html=True)

# ============================================================
# 2. TIĂU Äá»€
# ============================================================
col1, col2 = st.columns([1, 4])
with col1:
    st.image(BOT_AVATAR, width=80)
with col2:
    st.title("RBXRC7 AI")
    st.caption("Trá»£ lĂ½ AI thĂ´ng minh, tĂ­ch há»£p bá»™ nhá»› ngá»¯ cáº£nh & pháº£n há»“i theo thá»i gian thá»±c")

# ============================================================
# 3. THANH BĂN: API KEY + TĂ™Y CHá»ŒN
# ============================================================
with st.sidebar:
    st.image(BOT_AVATAR, caption="Há»‡ thá»‘ng RBXRC7 AI", use_container_width=True)

    api_key = st.text_input("đŸ”‘ Nháº­p Gemini API Key:", type="password")

    st.divider()
    st.subheader("â™ï¸ TĂ¹y chá»‰nh")

    model_choice = st.selectbox(
        "MĂ´ hĂ¬nh:",
        options=["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.5-flash-lite"],
        index=0,
        help="Flash: nhanh, cĂ¢n báº±ng. Pro: suy luáº­n sĂ¢u hÆ¡n, cháº­m hÆ¡n. Flash-Lite: siĂªu nhanh, tiáº¿t kiá»‡m."
    )

    temperature = st.slider(
        "Äá»™ sĂ¡ng táº¡o (temperature):",
        min_value=0.0, max_value=1.5, value=0.7, step=0.1,
        help="GiĂ¡ trá»‹ cĂ ng cao cĂ¢u tráº£ lá»i cĂ ng sĂ¡ng táº¡o/ngáº«u nhiĂªn; cĂ ng tháº¥p cĂ ng chĂ­nh xĂ¡c/á»•n Ä‘á»‹nh."
    )

    custom_persona = st.text_area(
        "TĂ­nh cĂ¡ch / vai trĂ² tĂ¹y chá»‰nh (tuá»³ chá»n):",
        placeholder="VĂ­ dá»¥: HĂ£y tráº£ lá»i ngáº¯n gá»n, dĂ¹ng vĂ­ dá»¥ thá»±c táº¿, giá»ng vÄƒn hĂ i hÆ°á»›c...",
        height=90
    )

    st.divider()
    col_a, col_b = st.columns(2)
    with col_a:
        clear_clicked = st.button("đŸ—‘ï¸ XoĂ¡ há»™i thoáº¡i", use_container_width=True)
    with col_b:
        if st.session_state.get("messages"):
            chat_text = "\n\n".join(
                f"{m['role'].upper()}: {m['content']}" for m in st.session_state["messages"]
            )
            st.download_button(
                "đŸ’¾ Táº£i vá»", data=chat_text, file_name="rbxrc7_chat.txt",
                use_container_width=True
            )

if not api_key:
    st.info("Vui lĂ²ng nháº­p Gemini API Key á»Ÿ thanh bĂªn trĂ¡i Ä‘á»ƒ báº¯t Ä‘áº§u trĂ² chuyá»‡n.", icon="đŸ”‘")
    st.stop()

os.environ["GOOGLE_API_KEY"] = api_key

# ============================================================
# 4. KHá»I Táº O MĂ” HĂŒNH + PROMPT
# ============================================================
BASE_SYSTEM_PROMPT = (
    "Báº¡n lĂ  RBXRC7, má»™t trá»£ lĂ½ AI thĂ´ng minh, linh hoáº¡t, thĂ¢n thiá»‡n vĂ  trung thá»±c. "
    "Biá»ƒu tÆ°á»£ng cá»§a báº¡n lĂ  logo chá»¯ R xanh cyan khĂ©p kĂ­n trong Ä‘Æ°á»ng trĂ²n cĂ´ng nghá»‡. "
    "Khi giá»›i thiá»‡u báº£n thĂ¢n, luĂ´n xÆ°ng tĂªn RBXRC7. "
    "Tráº£ lá»i rĂµ rĂ ng, cĂ³ cáº¥u trĂºc khi cáº§n (dĂ¹ng gáº¡ch Ä‘áº§u dĂ²ng, vĂ­ dá»¥ cá»¥ thá»ƒ), "
    "thá»«a nháº­n khi khĂ´ng cháº¯c cháº¯n thay vĂ¬ bá»‹a Ä‘áº·t thĂ´ng tin, vĂ  giá»¯ giá»ng vÄƒn tá»± nhiĂªn, gáº§n gÅ©i báº±ng tiáº¿ng Viá»‡t "
    "trá»« khi ngÆ°á»i dĂ¹ng chá»§ Ä‘á»™ng dĂ¹ng ngĂ´n ngá»¯ khĂ¡c."
)


def build_chain(model_name: str, temp: float, persona: str):
    llm = ChatGoogleGenerativeAI(
        model=model_name,
        temperature=temp,
        streaming=True,
    )

    system_prompt = BASE_SYSTEM_PROMPT
    if persona.strip():
        system_prompt += f"\n\nGhi chĂº thĂªm vá» phong cĂ¡ch tráº£ lá»i do ngÆ°á»i dĂ¹ng yĂªu cáº§u: {persona.strip()}"

    prompt = ChatPromptTemplate.from_messages([
        ("system", system_prompt),
        MessagesPlaceholder(variable_name="chat_history"),
        ("human", "{input}")
    ])

    return prompt | llm


# XĂ¢y láº¡i chain má»—i khi model/temperature/persona thay Ä‘á»•i (khĂ´ng cache_resource
# vĂ¬ cĂ¡c tham sá»‘ nĂ y cĂ³ thá»ƒ thay Ä‘á»•i liĂªn tá»¥c qua sidebar)
chain = build_chain(model_choice, temperature, custom_persona)

# ============================================================
# 5. Bá»˜ NHá» Há»˜I THOáº I
# ============================================================
if "store" not in st.session_state:
    st.session_state.store = {}

if "messages" not in st.session_state:
    st.session_state.messages = []

if clear_clicked:
    st.session_state.messages = []
    st.session_state.store = {}
    st.rerun()


def get_session_history(session_id: str):
    if session_id not in st.session_state.store:
        st.session_state.store[session_id] = ChatMessageHistory()
    return st.session_state.store[session_id]


chatbot = RunnableWithMessageHistory(
    chain,
    get_session_history,
    input_messages_key="input",
    history_messages_key="chat_history",
)

# ============================================================
# 6. HIá»‚N THá» Lá»CH Sá»¬ TRĂ’ CHUYá»†N
# ============================================================
if not st.session_state.messages:
    st.markdown(
        "đŸ‘‹ **Xin chĂ o! MĂ¬nh lĂ  RBXRC7.** Há»i mĂ¬nh báº¥t cá»© Ä‘iá»u gĂ¬ â€” láº­p trĂ¬nh, há»c táº­p, "
        "viáº¿t lĂ¡ch, hay chá»‰ Ä‘á»ƒ trĂ² chuyá»‡n cho vui!"
    )

for msg in st.session_state.messages:
    avatar = BOT_AVATAR if msg["role"] == "assistant" else None
    with st.chat_message(msg["role"], avatar=avatar):
        st.markdown(msg["content"])

# ============================================================
# 7. Xá»¬ LĂ CĂ‚U Há»I Má»I (streaming + xá»­ lĂ½ lá»—i)
# ============================================================
if user_input := st.chat_input("Há»i RBXRC7 báº¥t ká»³ Ä‘iá»u gĂ¬..."):
    st.session_state.messages.append({"role": "user", "content": user_input})
    with st.chat_message("user"):
        st.markdown(user_input)

    with st.chat_message("assistant", avatar=BOT_AVATAR):
        placeholder = st.empty()
        full_reply = ""
        try:
            for chunk in chatbot.stream(
                {"input": user_input},
                config={"configurable": {"session_id": "rbxrc7_session"}}
            ):
                # chunk lĂ  AIMessageChunk; ná»™i dung náº±m á»Ÿ .content
                token = getattr(chunk, "content", "") or ""
                full_reply += token
                placeholder.markdown(full_reply + "â–Œ")
            placeholder.markdown(full_reply if full_reply else "*(KhĂ´ng cĂ³ pháº£n há»“i)*")
        except Exception as e:
            full_reply = (
                "â ï¸ ÄĂ£ xáº£y ra lá»—i khi gá»i mĂ´ hĂ¬nh. Vui lĂ²ng kiá»ƒm tra API Key, "
                "háº¡n má»©c sá»­ dá»¥ng (quota), hoáº·c thá»­ láº¡i sau.\n\n"
                f"Chi tiáº¿t lá»—i: `{e}`"
            )
            placeholder.error(full_reply)

    st.session_state.messages.append({"role": "assistant", "content": full_reply})
