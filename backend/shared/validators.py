def luhn_valid(number: str) -> bool:
    """Algoritmo de Luhn para validar números de tarjeta."""
    if not number.isdigit():
        return False
    total = 0
    for i, ch in enumerate(reversed(number)):
        digit = int(ch)
        if i % 2 == 1:
            digit *= 2
            if digit > 9:
                digit -= 9
        total += digit
    return total % 10 == 0


def detect_brand(number: str) -> str:
    if number.startswith("4"):
        return "visa"
    if number[:2] in {"51", "52", "53", "54", "55"} or (
        number[:4].isdigit() and 2221 <= int(number[:4]) <= 2720
    ):
        return "mastercard"
    if number[:2] in {"34", "37"}:
        return "amex"
    return "desconocida"
