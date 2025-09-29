import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';
import 'package:moyasar/src/utils/card_utils.dart';
import 'package:moyasar/src/utils/input_formatters.dart';
import 'package:moyasar/src/utils/card_network_utils.dart';
import 'package:moyasar/src/widgets/network_icons.dart';
import 'package:moyasar/src/widgets/three_d_s_webview.dart';

/// The widget that shows the Credit Card form and manages the 3DS step.
class CreditCard extends StatefulWidget {
  CreditCard(
      {super.key,
        required this.config,
        required this.onPaymentResult,
        this.locale = const Localization.en()})
      : textDirection =
  locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  final Function onPaymentResult;
  final PaymentConfig config;
  final Localization locale;
  final TextDirection textDirection;

  @override
  State<CreditCard> createState() => _CreditCardState();
}

class _CreditCardState extends State<CreditCard> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _cardData = CardFormModel();

  AutovalidateMode _autoValidateMode = AutovalidateMode.onUserInteraction;

  bool _isSubmitting = false;
  bool _tokenizeCard = false;
  bool _manualPayment = false;

  // Network detection state
  CardNetwork? _detectedNetwork;
  bool _unsupportedNetwork = false;

  // Error state for each field
  String? _nameError;
  String? _cardNumberError;
  String? _expiryError;
  String? _cvcError;

  // Track if fields have been filled
  bool _nameFieldFilled = false;
  bool _cardNumberFieldFilled = false;
  bool _expiryFieldFilled = false;
  bool _cvcFieldFilled = false;

  @override
  void initState() {
    super.initState();
    setState(() {
      _tokenizeCard = widget.config.creditCard?.saveCard ?? false;
      _manualPayment = widget.config.creditCard?.manual ?? false;
    });
  }

  // Check if button should be enabled
  bool get _isButtonEnabled {
    // Check if all fields are filled and there are no errors
    bool allFieldsFilled = _nameFieldFilled &&
        _cardNumberFieldFilled &&
        _expiryFieldFilled &&
        _cvcFieldFilled;

    bool noErrors = _nameError == null &&
        _cardNumberError == null &&
        _expiryError == null &&
        _cvcError == null;

    return allFieldsFilled && noErrors && !_isSubmitting;
  }

  void _saveForm() async {
    if (!_isButtonEnabled) return;

    closeKeyboard();

    bool isValidForm =
        _formKey.currentState != null && _formKey.currentState!.validate();

    if (!isValidForm) {
      setState(() => _autoValidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    _formKey.currentState?.save();

    final source = CardPaymentRequestSource(
        creditCardData: _cardData,
        tokenizeCard: _tokenizeCard,
        manualPayment: _manualPayment);
    final paymentRequest = PaymentRequest(widget.config, source);

    setState(() => _isSubmitting = true);

    final result = await Moyasar.pay(
        apiKey: widget.config.publishableApiKey,
        paymentRequest: paymentRequest);

    setState(() => _isSubmitting = false);

    if (result is! PaymentResponse ||
        result.status != PaymentStatus.initiated) {
      widget.onPaymentResult(result);
      return;
    }

    final String transactionUrl =
        (result.source as CardPaymentResponseSource).transactionUrl;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
            fullscreenDialog: true,
            maintainState: false,
            builder: (context) => ThreeDSWebView(
                transactionUrl: transactionUrl,
                on3dsDone: (String status, String message) async {
                  if (status == PaymentStatus.paid.name) {
                    result.status = PaymentStatus.paid;
                  } else if (status == PaymentStatus.authorized.name) {
                    result.status = PaymentStatus.authorized;
                  } else {
                    result.status = PaymentStatus.failed;
                    (result.source as CardPaymentResponseSource).message =
                        message;
                  }
                  Navigator.pop(context);
                  widget.onPaymentResult(result);
                })),
      );
    }
  }

  // Validate name on change
  void _validateName(String? value) {
    setState(() {
      _nameError = CardUtils.validateName(value, widget.locale);
      _nameFieldFilled = value != null && value.trim().isNotEmpty;
    });
  }

  // Validate card number on change
  void _validateCardNumber(String? value) {
    setState(() {
      _cardNumberError = CardUtils.validateCardNum(value, widget.locale);
      _cardNumberFieldFilled =
          value != null && value.replaceAll(' ', '').length >= 13;

      if (value != null && value.isNotEmpty) {
        final cleaned = value.replaceAll(RegExp(r'\D'), '');

        if (cleaned.length >= 4) {
          final detected = detectNetwork(cleaned);

          if (detected != CardNetwork.unknown) {
            _detectedNetwork = detected;

            final supported = widget.config.supportedNetworks.map((e) => e.name).toSet();
            final detectedName = detected.name;

            if (!supported.contains(detectedName)) {
              _unsupportedNetwork = true;
              _cardNumberError = widget.locale.unsupportedNetwork;
            } else {
              _unsupportedNetwork = false;
            }
          } else {
            _detectedNetwork = null;
            _unsupportedNetwork = false;
          }
        } else {
          _detectedNetwork = null;
          _unsupportedNetwork = false;
        }
      } else {
        _detectedNetwork = null;
        _unsupportedNetwork = false;
      }
    });
  }

  // Validate expiry date on change
  void _validateExpiry(String? value) {
    setState(() {
      final cleanValue = value?.replaceAll('\u200E', '') ?? '';
      _expiryError = CardUtils.validateDate(cleanValue, widget.locale);
      _expiryFieldFilled = cleanValue.length >= 5; // MM/YY format
    });
  }

  // Validate CVC on change
  void _validateCVC(String? value) {
    setState(() {
      _cvcError = CardUtils.validateCVC(value, widget.locale);
      _cvcFieldFilled = value != null && value.length >= 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      autovalidateMode: _autoValidateMode,
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardFormField(
            inputDecoration: buildInputDecoration(
                hintText: widget.locale.nameOnCard,
                hideBorder: false,
                hintTextDirection: widget.textDirection),
            keyboardType: TextInputType.text,
            onChanged: _validateName,
            onSaved: (value) => _cardData.name = value ?? '',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z. ]')),
            ],
          ),
          SizedBox(
            height: 16,
          ),
          CardFormField(
            inputDecoration: buildInputDecoration(
                hintText: widget.locale.cardNumber,
                hintTextDirection: widget.textDirection,
                hideBorder: false,
                addNetworkIcons: true,
                config: widget.config,
                detectedNetwork: _detectedNetwork,
                unsupportedNetwork: _unsupportedNetwork),
            onChanged: _validateCardNumber,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
              CardNumberInputFormatter(),
            ],
            onSaved: (value) =>
            _cardData.number = CardUtils.getCleanedNumber(value!),
          ),
          SizedBox(
            height: 16,
          ),
          CardFormField(
            inputDecoration: buildInputDecoration(
              hintText: '${widget.locale.expiry} (MM / YY)',
              hintTextDirection: widget.textDirection,
              hideBorder: false,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
              CardMonthInputFormatter(),
            ],
            onChanged: _validateExpiry,
            onSaved: (value) {
              List<String> expireDate = CardUtils.getExpiryDate(
                  value!.replaceAll('\u200E', ''));
              _cardData.month =
                  expireDate.first.replaceAll('\u200E', '');
              _cardData.year =
                  expireDate[1].replaceAll('\u200E', '');
            },
          ),
          SizedBox(
            height: 16,
          ),
          CardFormField(
            inputDecoration: buildInputDecoration(
              hintText: widget.locale.cvc,
              hintTextDirection: widget.textDirection,
              hideBorder: false,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: _validateCVC,
            onSaved: (value) => _cardData.cvc = value ?? '',
          ),
          SizedBox(
            height: 8,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
              child: ElevatedButton(
                style: ButtonStyle(
                  minimumSize:
                  const WidgetStatePropertyAll<Size>(Size.fromHeight(52)),
                  backgroundColor: WidgetStatePropertyAll<Color>(
                    _isButtonEnabled ? blueColor : lightBlueColor,
                  ),
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                onPressed: _isButtonEnabled ? _saveForm : null,
                child: _isSubmitting
                    ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                )
                    : Directionality(
                  textDirection: widget.textDirection,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textDirection: widget.textDirection,
                    children: [
                      Spacer(),
                      Text(
                        '${widget.locale.pay} ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textDirection: widget.textDirection,
                      ),
                      Text(
                        '${"SAR"} ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textDirection: widget.textDirection,
                      ),
                      Text(
                        getAmount(widget.config.amount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: "RobotoMono"
                        ),
                        textDirection: widget.textDirection,
                      ),
                      Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SaveCardNotice(
            tokenizeCard: _tokenizeCard,
            locale: widget.locale,
            textDirection: widget.textDirection,
          ),
        ],
      ),
    );
  }
}

class SaveCardNotice extends StatelessWidget {
  const SaveCardNotice({
    super.key,
    required this.tokenizeCard,
    required this.locale,
    required this.textDirection,
  });

  final bool tokenizeCard;
  final Localization locale;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final isRTL = textDirection == TextDirection.rtl;

    return tokenizeCard
        ? Padding(
        padding: const EdgeInsets.all(8.0),
        child: Directionality(
          textDirection: textDirection,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            textDirection: textDirection,
            children: [
              Icon(
                Icons.info,
                color: blueColor,
              ),
              SizedBox(width: 5),
              Flexible(
                child: Text(
                  locale.saveCardNotice,
                  style: TextStyle(color: blueColor),
                  textDirection: textDirection,
                  textAlign: isRTL ? TextAlign.right : TextAlign.left,
                ),
              ),
            ],
          ),
        ))
        : const SizedBox.shrink();
  }
}

class CardFormField extends StatelessWidget {
  final void Function(String?)? onSaved;
  final String? Function(String?)? validator;
  final void Function(String?)? onChanged;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final InputDecoration? inputDecoration;

  const CardFormField(
      {super.key,
        required this.onSaved,
        this.validator,
        this.onChanged,
        this.inputDecoration,
        this.keyboardType = TextInputType.number,
        this.textInputAction = TextInputAction.next,
        this.inputFormatters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: TextFormField(
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        decoration: inputDecoration,
        validator: validator,
        onSaved: onSaved,
        onChanged: onChanged,
        style: TextStyle(
          fontFamily: "RobotoMono",
        ),
        inputFormatters: inputFormatters,
        textDirection: inputDecoration?.hintTextDirection,
        textAlign: inputDecoration?.hintTextDirection == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
      ),
    );
  }
}

String showAmount(int amount, String currency, Localization locale) {
  final formattedAmount = (amount / 100).toStringAsFixed(2);
  return '${locale.pay} $currency $formattedAmount';
}

String getAmount(int amount) {
  final formattedAmount = (amount / 100).toStringAsFixed(2);
  return formattedAmount;
}

InputDecoration buildInputDecoration(
    {required String hintText,
      required TextDirection hintTextDirection,
      bool addNetworkIcons = false,
      bool hideBorder = false,
      PaymentConfig? config,
      CardNetwork? detectedNetwork,
      bool unsupportedNetwork = false}) {
  Widget? iconWidget;
  if (addNetworkIcons && config != null) {
    if (detectedNetwork != null) {
      final supported = config.supportedNetworks.map((e) => e.name).toSet();
      final detectedName = detectedNetwork.name;
      if (supported.contains(detectedName)) {
        // Show only the detected network icon when it's supported
        iconWidget = NetworkIcons(
          config: PaymentConfig(
            publishableApiKey: config.publishableApiKey,
            amount: config.amount,
            currency: config.currency,
            description: config.description,
            supportedNetworks: [PaymentNetwork.values.firstWhere((e) => e.name == detectedName)],
          ),
          textDirection: hintTextDirection,
        );
      } else {
        // Show all configured networks when detected network is not supported
        iconWidget = NetworkIcons(
          config: config,
          textDirection: hintTextDirection,
        );
      }
    } else {
      // Show all configured networks when no network is detected or there are errors
      iconWidget = NetworkIcons(
        config: config,
        textDirection: hintTextDirection,
      );
    }
  }

  final isRTL = hintTextDirection == TextDirection.rtl;

  return InputDecoration(
    suffixIcon: isRTL ? null : iconWidget,
    prefixIcon: isRTL ? iconWidget : null,
    hintText: hintText,
    border:  OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.blue, width: 2.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.red, width: 2.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.red, width: 2.0),
      borderRadius: BorderRadius.circular(8.0),
    ),

    isDense: true,
    filled: true,
    fillColor: Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintTextDirection: hintTextDirection,
  );
}

void closeKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

Color blueColor = Colors.blue[700]!;
Color lightBlueColor = Colors.blue[100]!;
